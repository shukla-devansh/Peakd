//  WorkoutShareSheet.swift
//  Pick a format (Story, Square, Sticker), choose whether to show weights, then share a 1080 px
//  PNG through the system share sheet (Instagram, Messages, Save Image…). Sticker is transparent.

import ImageIO
import SwiftUI
import UniformTypeIdentifiers

struct WorkoutShareSheet: View {
    let data: WorkoutShareData

    @Environment(\.dismiss) private var dismiss
    @AppStorage("shareStyle") private var style: ShareStyle = .story
    @AppStorage("shareShowsWeights") private var showsWeights = true
    @State private var image: SharedImage?

    var body: some View {
        NavigationStack {
            VStack(spacing: Space.md) {
                preview
                    .frame(maxHeight: .infinity)
                CadSegmentedControl(ShareStyle.allCases, selection: $style) { $0.title }
                    .accessibilityLabel("Card format")
                Toggle("Show weights", isOn: $showsWeights)
                    .font(.cadBody)
                    .tint(Palette.accent)
                    .frame(minHeight: Size.minTouch)
                if let image {
                    ShareLink(item: image, preview: SharePreview(data.title, image: Image(decorative: image.previewImage, scale: 3))) {
                        Label("Share", systemImage: "square.and.arrow.up")
                    }
                    .buttonStyle(.cadPrimary)
                } else {
                    Button("Share") {}
                        .buttonStyle(.cadPrimary)
                        .disabled(true)
                }
            }
            .padding(.horizontal, Space.screenMargin)
            .padding(.bottom, Space.xs)
            .foregroundStyle(Palette.text)
            .background(Palette.surface.ignoresSafeArea())
            .navigationTitle("Share workout")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
            .task(id: "\(style.rawValue)-\(showsWeights)") { render() }
        }
        .presentationDragIndicator(.visible)
        .presentationBackground(Palette.surface)
        .tint(Palette.accentText)
        .preferredColorScheme(.dark)
    }

    /// The card scaled to fit; the sticker sits on a checkerboard so its transparency shows.
    private var preview: some View {
        GeometryReader { geo in
            let size = style.size
            let scale = min(geo.size.width / size.width, geo.size.height / size.height, 1)
            ZStack {
                if style == .sticker {
                    VStack(spacing: Space.xs) {
                        WorkoutShareCard(data: data, style: style, showsWeights: showsWeights)
                            .scaleEffect(scale)
                            .frame(width: size.width * scale, height: size.height * scale)
                            .background(Checkerboard().clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous)))
                        Text("Transparent background: add it on top of your own photo in Instagram or Photos.")
                            .font(.cadFootnote)
                            .foregroundStyle(Palette.textSecondary)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                } else {
                    WorkoutShareCard(data: data, style: style, showsWeights: showsWeights)
                        .clipShape(RoundedRectangle(cornerRadius: 24 / max(scale, 0.01), style: .continuous))
                        .scaleEffect(scale)
                        .frame(width: size.width * scale, height: size.height * scale)
                        .shadow(color: .black.opacity(0.4), radius: 16, y: 8)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(.top, Space.xs)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Preview of the \(style.title.lowercased()) card for \(data.title)")
    }

    private func render() {
        let renderer = ImageRenderer(content: WorkoutShareCard(data: data, style: style, showsWeights: showsWeights))
        renderer.scale = 3
        renderer.isOpaque = style != .sticker
        guard let cg = renderer.cgImage, let png = Self.png(cg) else { image = nil; return }
        // The share sheet's thumbnail is drawn on a light or dark card; give the transparent
        // sticker a dark backing there so its white text doesn't disappear.
        var preview = cg
        if style == .sticker {
            let backed = ImageRenderer(content: WorkoutShareCard(data: data, style: style, showsWeights: showsWeights)
                .background(Palette.background))
            backed.scale = 3
            preview = backed.cgImage ?? cg
        }
        image = SharedImage(cgImage: cg, previewImage: preview, data: png, filename: "\(data.title) · \(AppInfo.name).png")
    }

    static func png(_ image: CGImage) -> Data? {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image, nil)
        return CGImageDestinationFinalize(destination) ? data as Data : nil
    }
}

/// Grey/white squares: the usual sign for "this part is see-through".
private struct Checkerboard: View {
    var square: CGFloat = 10

    var body: some View {
        Canvas { context, size in
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color(white: 0.32)))
            let cols = Int(size.width / square) + 1, rows = Int(size.height / square) + 1
            for r in 0..<rows {
                for c in 0..<cols where (r + c).isMultiple(of: 2) {
                    context.fill(Path(CGRect(x: CGFloat(c) * square, y: CGFloat(r) * square, width: square, height: square)),
                                 with: .color(Color(white: 0.22)))
                }
            }
        }
        .accessibilityHidden(true)
    }
}

/// A rendered card, shared as a PNG file so apps keep the name and the transparency.
struct SharedImage: Transferable, @unchecked Sendable {
    let cgImage: CGImage
    /// Same image, with a dark backing for the sticker (share sheet thumbnail only).
    let previewImage: CGImage
    let data: Data
    let filename: String

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .png) { image in
            let safe = image.filename.replacingOccurrences(of: "/", with: "-")
            let url = URL.temporaryDirectory.appending(path: safe)
            try image.data.write(to: url, options: .atomic)
            return SentTransferredFile(url)
        }
    }
}

#Preview {
    Color.clear.sheet(isPresented: .constant(true)) {
        WorkoutShareSheet(data: .preview)
    }
}
