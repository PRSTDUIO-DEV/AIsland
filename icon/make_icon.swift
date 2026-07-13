#!/usr/bin/env swift
// AIsland icon — "island at night": glossy pill floating over dark water,
// three provider rings glowing, light columns reflecting on the sea below.
// Run: swift icon/make_icon.swift   (writes icon/AppIcon.iconset/*.png)
import AppKit

let S: CGFloat = 1024
let squircle = CGRect(x: 100, y: 100, width: 824, height: 824)
let corner: CGFloat = 185

let terracotta = CGColor(red: 0.85, green: 0.47, blue: 0.34, alpha: 1)
let teal = CGColor(red: 0.10, green: 0.66, blue: 0.52, alpha: 1)
let azure = CGColor(red: 0.35, green: 0.55, blue: 1.00, alpha: 1)

var seed: UInt64 = 42
func rnd() -> CGFloat {
    seed = seed &* 6364136223846793005 &+ 1442695040888963407
    return CGFloat((seed >> 33) % 10000) / 10000
}

func gradient(_ stops: [(CGFloat, CGColor)]) -> CGGradient {
    CGGradient(
        colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
        colors: stops.map(\.1) as CFArray,
        locations: stops.map(\.0)
    )!
}

func rgba(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat) -> CGColor {
    CGColor(red: r, green: g, blue: b, alpha: a)
}

func with(_ c: CGColor, alpha: CGFloat) -> CGColor { c.copy(alpha: alpha)! }

func draw(into ctx: CGContext) {
    let path = CGPath(roundedRect: squircle, cornerWidth: corner, cornerHeight: corner, transform: nil)
    ctx.addPath(path)
    ctx.clip()

    // Night sky: lighter charcoal at the top edge falling to near-black below.
    ctx.drawLinearGradient(
        gradient([(0, rgba(0.014, 0.015, 0.024, 1)), (0.6, rgba(0.035, 0.038, 0.058, 1)), (1, rgba(0.105, 0.110, 0.145, 1))]),
        start: CGPoint(x: 512, y: 100), end: CGPoint(x: 512, y: 924), options: []
    )

    // Aurora washes hugging the pill.
    ctx.drawRadialGradient(
        gradient([(0, with(terracotta, alpha: 0.13)), (1, with(terracotta, alpha: 0))]),
        startCenter: CGPoint(x: 340, y: 560), startRadius: 0,
        endCenter: CGPoint(x: 340, y: 560), endRadius: 340, options: []
    )
    ctx.drawRadialGradient(
        gradient([(0, with(teal, alpha: 0.15)), (1, with(teal, alpha: 0))]),
        startCenter: CGPoint(x: 512, y: 600), startRadius: 0,
        endCenter: CGPoint(x: 512, y: 600), endRadius: 350, options: []
    )
    ctx.drawRadialGradient(
        gradient([(0, with(azure, alpha: 0.14)), (1, with(azure, alpha: 0))]),
        startCenter: CGPoint(x: 690, y: 560), startRadius: 0,
        endCenter: CGPoint(x: 690, y: 560), endRadius: 340, options: []
    )

    // Stars — sparse, sky only.
    for _ in 0 ..< 42 {
        let x = 130 + rnd() * 760
        let y = 480 + rnd() * 420
        let r = 0.8 + rnd() * 1.8
        ctx.setFillColor(rgba(1, 1, 1, 0.04 + rnd() * 0.13))
        ctx.fillEllipse(in: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2))
    }

    // Pill geometry — floats slightly above center.
    let pillW: CGFloat = 560, pillH: CGFloat = 172
    let pillRect = CGRect(x: 512 - pillW / 2, y: 510 - pillH / 2, width: pillW, height: pillH)
    let pill = CGPath(roundedRect: pillRect, cornerWidth: pillH / 2, cornerHeight: pillH / 2, transform: nil)

    let ringXs: [CGFloat] = [512 - 172, 512, 512 + 172]
    let ringColors = [terracotta, teal, azure]

    // Pill: drop shadow, body gradient, gloss, hairline edge.
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -20), blur: 40, color: rgba(0, 0, 0, 0.55))
    ctx.addPath(pill)
    ctx.setFillColor(rgba(0, 0, 0, 1))
    ctx.fillPath()
    ctx.restoreGState()

    ctx.saveGState()
    ctx.addPath(pill)
    ctx.clip()
    ctx.drawLinearGradient(
        gradient([(0, rgba(0, 0, 0, 1)), (0.72, rgba(0.055, 0.058, 0.075, 1)), (1, rgba(0.10, 0.105, 0.13, 1))]),
        start: CGPoint(x: 512, y: pillRect.minY), end: CGPoint(x: 512, y: pillRect.maxY), options: []
    )
    ctx.drawLinearGradient(
        gradient([(0, rgba(1, 1, 1, 0.16)), (1, rgba(1, 1, 1, 0))]),
        start: CGPoint(x: 512, y: pillRect.maxY), end: CGPoint(x: 512, y: pillRect.maxY - 26), options: []
    )
    ctx.restoreGState()

    ctx.addPath(pill)
    ctx.setStrokeColor(rgba(1, 1, 1, 0.10))
    ctx.setLineWidth(2)
    ctx.strokePath()

    // Rings: dim track, glow pass, crisp pass.
    let radius: CGFloat = 54
    let lineW: CGFloat = 15
    let fractions: [CGFloat] = [0.68, 0.52, 0.30]
    let cy = pillRect.midY
    ctx.setLineCap(.round)
    for ((x, c), f) in zip(zip(ringXs, ringColors), fractions) {
        ctx.setLineWidth(lineW)
        ctx.setStrokeColor(rgba(1, 1, 1, 0.13))
        ctx.addArc(center: CGPoint(x: x, y: cy), radius: radius,
                   startAngle: 0, endAngle: 2 * .pi, clockwise: false)
        ctx.strokePath()

        let start = CGFloat.pi / 2
        let end = start - f * 2 * .pi
        ctx.saveGState()
        ctx.setShadow(offset: .zero, blur: 30, color: with(c, alpha: 0.95))
        ctx.setStrokeColor(c)
        ctx.addArc(center: CGPoint(x: x, y: cy), radius: radius,
                   startAngle: start, endAngle: end, clockwise: true)
        ctx.strokePath()
        ctx.restoreGState()

        ctx.setStrokeColor(c)
        ctx.addArc(center: CGPoint(x: x, y: cy), radius: radius,
                   startAngle: start, endAngle: end, clockwise: true)
        ctx.strokePath()
    }

    // Soft light beams falling below the pill — elongated radial blobs, feathered.
    for (x, c) in zip(ringXs, ringColors) {
        ctx.saveGState()
        ctx.clip(to: CGRect(x: x - 70, y: 140, width: 140, height: pillRect.minY - 146))
        ctx.translateBy(x: x, y: pillRect.minY - 14)
        ctx.scaleBy(x: 1, y: 4.0)
        ctx.drawRadialGradient(
            gradient([(0, with(c, alpha: 0.34)), (1, with(c, alpha: 0))]),
            startCenter: .zero, startRadius: 0,
            endCenter: .zero, endRadius: 36, options: []
        )
        ctx.restoreGState()
    }

    // Diagonal sheen across the top glass.
    ctx.drawLinearGradient(
        gradient([(0, rgba(1, 1, 1, 0.05)), (0.45, rgba(1, 1, 1, 0.012)), (1, rgba(1, 1, 1, 0))]),
        start: CGPoint(x: 220, y: 924), end: CGPoint(x: 700, y: 430), options: []
    )

    // Edge vignette + rim highlight.
    ctx.drawRadialGradient(
        gradient([(0, rgba(0, 0, 0, 0)), (0.78, rgba(0, 0, 0, 0)), (1, rgba(0, 0, 0, 0.34))]),
        startCenter: CGPoint(x: 512, y: 512), startRadius: 0,
        endCenter: CGPoint(x: 512, y: 512), endRadius: 620, options: []
    )
    ctx.addPath(path)
    ctx.setStrokeColor(rgba(1, 1, 1, 0.06))
    ctx.setLineWidth(2)
    ctx.strokePath()
}

func makeContext(_ px: Int) -> CGContext {
    CGContext(
        data: nil, width: px, height: px, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
}

let master = makeContext(Int(S))
draw(into: master)
guard let masterImage = master.makeImage() else { fatalError("render failed") }

let outDir = URL(fileURLWithPath: "icon/AppIcon.iconset")
try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

let outputs: [(String, Int)] = [
    ("icon_16x16.png", 16), ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32), ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128), ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256), ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512), ("icon_512x512@2x.png", 1024),
]
for (name, px) in outputs {
    let ctx = makeContext(px)
    ctx.interpolationQuality = .high
    ctx.draw(masterImage, in: CGRect(x: 0, y: 0, width: px, height: px))
    guard let img = ctx.makeImage() else { fatalError("scale \(px) failed") }
    let rep = NSBitmapImageRep(cgImage: img)
    guard let png = rep.representation(using: .png, properties: [:]) else { fatalError("png \(px) failed") }
    try! png.write(to: outDir.appendingPathComponent(name))
}
print("wrote \(outputs.count) PNGs")
