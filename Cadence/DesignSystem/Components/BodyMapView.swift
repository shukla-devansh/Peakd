//  BodyMapView.swift
//  Front and back body drawn in code. Each muscle area is tinted bluer the more sets it got
//  (same scale as the training calendar). The figure is decorative: callers give VoiceOver the
//  numbers (Progress keeps its percentage bars under the map).

import SwiftUI

struct BodyMapView: View {
    /// 0…1 per muscle group (1 = the most-trained group).
    let intensity: [MuscleGroup: Double]
    var showsLabels = true

    var body: some View {
        HStack(alignment: .top, spacing: Space.md) {
            figure(BodyShapes.front, label: "Front")
            figure(BodyShapes.back, label: "Back")
        }
        .accessibilityHidden(true)
    }

    private func figure(_ regions: [BodyRegion], label: String) -> some View {
        VStack(spacing: 6) {
            Canvas { context, size in
                let scale = min(size.width / BodyShapes.canvas.width, size.height / BodyShapes.canvas.height)
                let dx = (size.width - BodyShapes.canvas.width * scale) / 2
                let transform = CGAffineTransform(translationX: dx, y: 0).scaledBy(x: scale, y: scale)
                for region in regions {
                    let path = region.path.applying(transform)
                    context.fill(path, with: .color(color(for: region.muscle)))
                }
            }
            .aspectRatio(BodyShapes.canvas.width / BodyShapes.canvas.height, contentMode: .fit)
            if showsLabels {
                Text(label)
                    .font(.cadLabel)
                    .foregroundStyle(Palette.textSecondary)
            }
        }
        .frame(maxWidth: .infinity)
    }

    /// Untrained: neutral. Trained: four steps of blue, never fainter than step 1.
    private func color(for muscle: MuscleGroup?) -> Color {
        guard let muscle else { return Palette.lineStrong }
        let value = intensity[muscle] ?? 0
        guard value > 0 else { return Palette.elevated.mix(with: Palette.lineStrong, by: 0.5) }
        let level = min(4, max(1, Int((value * 4).rounded(.up))))
        return TrainingCalendarCard.fills[level]
    }

    /// Sets per muscle → 0…1 relative to the most-trained group. Full-body sets count for every group.
    static func intensity(from shares: [MuscleShare]) -> [MuscleGroup: Double] {
        var sets: [MuscleGroup: Double] = [:]
        let fullBody = Double(shares.first { $0.muscle == .fullBody }?.sets ?? 0)
        for share in shares where share.muscle != .fullBody { sets[share.muscle] = Double(share.sets) }
        if fullBody > 0 {
            for m in MuscleGroup.allCases where m != .fullBody { sets[m, default: 0] += fullBody }
        }
        let top = sets.values.max() ?? 0
        guard top > 0 else { return [:] }
        return sets.mapValues { $0 / top }
    }
}

struct BodyRegion {
    /// nil = not a trained area (head, hands, joints).
    let muscle: MuscleGroup?
    let path: Path
}

/// A simple mannequin on a 100 × 177 canvas (head to feet), mirrored left/right.
enum BodyShapes {
    static let canvas = CGSize(width: 100, height: 177)

    private static func rect(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ r: CGFloat) -> Path {
        Path(roundedRect: CGRect(x: x, y: y, width: w, height: h), cornerRadius: r, style: .continuous)
    }

    private static func oval(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> Path {
        Path(ellipseIn: CGRect(x: x, y: y, width: w, height: h))
    }

    private static func poly(_ points: [CGPoint]) -> Path {
        var p = Path()
        p.addLines(points)
        p.closeSubpath()
        return p
    }

    /// The same shape on both sides of the body (x mirrored around 50).
    private static func pair(_ muscle: MuscleGroup?, _ make: (Bool) -> Path) -> [BodyRegion] {
        [BodyRegion(muscle: muscle, path: make(false)),
         BodyRegion(muscle: muscle, path: make(true).applying(CGAffineTransform(a: -1, b: 0, c: 0, d: 1, tx: 100, ty: 0)))]
    }

    private static var shared: [BodyRegion] {
        [BodyRegion(muscle: nil, path: oval(41.5, 2, 17, 20)),                 // head
         BodyRegion(muscle: nil, path: rect(46, 20, 8, 7, 2))]                 // neck
        + pair(.shoulders) { _ in oval(23.5, 26, 16, 15) }                      // deltoids
        + pair(.arms) { _ in rect(19, 67, 9.5, 25, 4.5) }                       // forearms
        + pair(nil) { _ in oval(18, 93, 10, 11) }                               // hands
        + pair(nil) { _ in oval(38, 127, 10, 6) }                               // knees
        + pair(nil) { _ in rect(36, 169, 13, 6, 3) }                            // feet
    }

    static let front: [BodyRegion] = shared
        + pair(.chest) { _ in rect(35, 28.5, 14.5, 15.5, 5.5) }                 // pecs
        + pair(.arms) { _ in rect(22, 41, 10.5, 25, 5) }                        // biceps
        + (0..<3).flatMap { row in                                              // abs, 2 × 3
            pair(.core) { _ in rect(41.5, 45.5 + CGFloat(row) * 9, 8, 8, 2.5) }
        }
        + pair(.core) { _ in rect(35, 46, 5, 24, 2.5) }                         // obliques
        + [BodyRegion(muscle: nil, path: rect(37, 73.5, 26, 12, 5))]            // hips
        + pair(.legs) { _ in rect(36, 86.5, 13, 40, 6) }                        // quads
        + pair(.legs) { _ in rect(38.5, 134, 9, 34, 4.5) }                      // shins

    static let back: [BodyRegion] = shared
        + [BodyRegion(muscle: .back, path: poly([                               // trapezius
            CGPoint(x: 43, y: 23), CGPoint(x: 57, y: 23), CGPoint(x: 64, y: 30),
            CGPoint(x: 50, y: 40), CGPoint(x: 36, y: 30)]))]
        + pair(.back) { _ in poly([                                             // lats
            CGPoint(x: 35.5, y: 32), CGPoint(x: 48.5, y: 41.5), CGPoint(x: 48.5, y: 62),
            CGPoint(x: 41, y: 59), CGPoint(x: 35, y: 44)]) }
        + [BodyRegion(muscle: .back, path: rect(41, 61.5, 18, 11.5, 4))]        // lower back
        + pair(.arms) { _ in rect(22, 41, 10.5, 25, 5) }                        // triceps
        + pair(.legs) { _ in oval(36.5, 73.5, 13.5, 15) }                       // glutes
        + pair(.legs) { _ in rect(36, 89.5, 13, 37, 6) }                        // hamstrings
        + pair(.legs) { _ in rect(37.5, 133.5, 10.5, 23, 5) }                   // calves
        + pair(nil) { _ in rect(39.5, 157, 7, 11.5, 3) }                        // lower legs
}

#Preview("Body map") {
    BodyMapView(intensity: [.legs: 1, .back: 0.7, .chest: 0.45, .shoulders: 0.2])
        .frame(height: 260)
        .padding()
        .previewSurface()
}
