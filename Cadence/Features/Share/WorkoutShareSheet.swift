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
                    ShareLink(item: image, preview: SharePreview(data.title, image: Image(decorative: image.cgImage, scale: 3))) {
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

    /// The card scaled to fit; the sticker sits on a photo-like gradient so its transparency shows.
    private var preview: some View {
        GeometryReader { geo in
            let size = style.size
            let scale = min(geo.size.width / size.width, geo.size.height / size.height, 1)
            ZStack {
                if style == .sticker {
                    LinearGradient(colors: [Color(white: 0.35), Color(white: 0.12)], startPoint: .top, endPoint: .bottom)
                        .frame(width: size.width * scale, height: size.width * scale * 1.25)
                        .overlay(alignment: .center) {
                            Image(systemName: "photo")
                                .font(.system(size: 40))
                                .foregroundStyle(.white.opacity(0.25))
                                .offset(y: -size.width * scale * 0.3)
                        }
                        .overlay(alignment: .bottom) {
                            WorkoutShareCard(data: data, style: style, showsWeights: showsWeights)
                                .scaleEffect(scale)
                                .frame(width: size.width * scale, height: size.height * scale)
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
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
        image = SharedImage(cgImage: cg, data: png, filename: "\(data.title) · \(AppInfo.name).png")
    }

    static func png(_ image: CGImage) -> Data? {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image, nil)
        return CGImageDestinationFinalize(destination) ? data as Data : nil
    }
}

/// A rendered card, shared as a PNG file so apps keep the name and the transparency.
struct SharedImage: Transferable, @unchecked Sendable {
    let cgImage: CGImage
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
