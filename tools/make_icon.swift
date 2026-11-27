// Regenerate the app icons: swift tools/make_icon.swift <output folder>, then copy the PNGs into
// Cadence/Assets.xcassets/AppIcon.appiconset (all three) and CadenceWatch/... (AppIcon.png).

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

// Peakd app icon: a rising training line that ends in a peak, on the app's dark background.
// Colours are the Theme tokens: background #0B0D10, surface #14171C, accent #2B64F0, accentText #7FA6FF.
enum Style { case standard, dark, tinted }

func color(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: a)
}

func render(_ style: Style, size: Int = 1024) -> CGImage {
    let s = CGFloat(size)
    let cs = CGColorSpace(name: CGColorSpace.sRGB)!
    let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0, space: cs,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    // CoreGraphics' origin is bottom-left; flip so y grows downwards like the design.
    ctx.translateBy(x: 0, y: s); ctx.scaleBy(x: 1, y: -1)

    // Background
    switch style {
    case .standard:
        ctx.setFillColor(color(0x0B0D10)); ctx.fill(CGRect(x: 0, y: 0, width: s, height: s))
        let g = CGGradient(colorsSpace: cs, colors: [color(0x16223F), color(0x0B0D10)] as CFArray, locations: [0, 1])!
        ctx.drawLinearGradient(g, start: CGPoint(x: 0, y: 0), end: CGPoint(x: s * 0.6, y: s), options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
        let glow = CGGradient(colorsSpace: cs, colors: [color(0x2B64F0, 0.55), color(0x2B64F0, 0)] as CFArray, locations: [0, 1])!
        ctx.drawRadialGradient(glow, startCenter: CGPoint(x: s * 0.76, y: s * 0.28), startRadius: 0,
                               endCenter: CGPoint(x: s * 0.76, y: s * 0.28), endRadius: s * 0.55, options: [])
    case .dark:
        ctx.setFillColor(color(0x0B0D10)); ctx.fill(CGRect(x: 0, y: 0, width: s, height: s))
        let glow = CGGradient(colorsSpace: cs, colors: [color(0x2B64F0, 0.35), color(0x2B64F0, 0)] as CFArray, locations: [0, 1])!
        ctx.drawRadialGradient(glow, startCenter: CGPoint(x: s * 0.76, y: s * 0.28), startRadius: 0,
                               endCenter: CGPoint(x: s * 0.76, y: s * 0.28), endRadius: s * 0.5, options: [])
    case .tinted:
        ctx.setFillColor(color(0x000000)); ctx.fill(CGRect(x: 0, y: 0, width: s, height: s))
    }

    // The line: low start, a dip, then a climb to the peak (kept inside the centre for the Watch's circle).
    let pts = [CGPoint(x: 0.20, y: 0.72), CGPoint(x: 0.40, y: 0.50), CGPoint(x: 0.53, y: 0.61), CGPoint(x: 0.76, y: 0.30)]
        .map { CGPoint(x: $0.x * s, y: $0.y * s) }
    let path = CGMutablePath(); path.addLines(between: pts)

    // Glow under the stroke, then the stroke.
    ctx.setLineCap(.round); ctx.setLineJoin(.round)
    if style != .tinted {
        ctx.setShadow(offset: .zero, blur: s * 0.05, color: color(0x2B64F0, 0.9))
    }
    ctx.addPath(path); ctx.setLineWidth(s * 0.075)
    ctx.setStrokeColor(style == .tinted ? color(0xFFFFFF) : color(0x7FA6FF)); ctx.strokePath()
    ctx.setShadow(offset: .zero, blur: 0, color: nil)

    // The peak: a bright dot with a ring.
    let peak = pts.last!
    ctx.setFillColor(style == .tinted ? color(0xFFFFFF) : color(0xFFFFFF))
    ctx.fillEllipse(in: CGRect(x: peak.x - s * 0.055, y: peak.y - s * 0.055, width: s * 0.11, height: s * 0.11))
    if style != .tinted {
        ctx.setStrokeColor(color(0x7FA6FF, 0.5)); ctx.setLineWidth(s * 0.018)
        ctx.strokeEllipse(in: CGRect(x: peak.x - s * 0.09, y: peak.y - s * 0.09, width: s * 0.18, height: s * 0.18))
    }
    return ctx.makeImage()!
}

func write(_ image: CGImage, to path: String) {
    let url = URL(fileURLWithPath: path)
    let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, image, nil)
    precondition(CGImageDestinationFinalize(dest))
}

let out = CommandLine.arguments[1]
write(render(.standard), to: out + "/AppIcon.png")
write(render(.dark), to: out + "/AppIcon-Dark.png")
write(render(.tinted), to: out + "/AppIcon-Tinted.png")
print("ok")
