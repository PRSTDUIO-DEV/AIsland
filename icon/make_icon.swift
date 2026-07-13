#!/usr/bin/env swift
import AppKit
import CoreGraphics
import Foundation

private let canvasPixels = 1024
private let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!

private enum IconBuildError: Error, CustomStringConvertible {
    case contextCreationFailed(Int, Int)
    case imageCreationFailed
    case pngEncodingFailed(String)

    var description: String {
        switch self {
        case .contextCreationFailed(let width, let height):
            return "Could not create bitmap context \(width)x\(height)."
        case .imageCreationFailed:
            return "Could not create CGImage from bitmap context."
        case .pngEncodingFailed(let name):
            return "Could not encode PNG for \(name)."
        }
    }
}

private extension CGFloat {
    var degreesToRadians: CGFloat { self * .pi / 180.0 }
}

private func color(_ hex: UInt32, alpha: CGFloat = 1.0) -> CGColor {
    let red = CGFloat((hex >> 16) & 0xff) / 255.0
    let green = CGFloat((hex >> 8) & 0xff) / 255.0
    let blue = CGFloat(hex & 0xff) / 255.0
    return CGColor(colorSpace: colorSpace, components: [red, green, blue, alpha])!
}

private func alpha(_ base: CGColor, _ value: CGFloat) -> CGColor {
    return base.copy(alpha: value)!
}

private func makeContext(width: Int, height: Int) throws -> CGContext {
    let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
    guard let context = CGContext(
        data: nil,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: width * 4,
        space: colorSpace,
        bitmapInfo: bitmapInfo
    ) else {
        throw IconBuildError.contextCreationFailed(width, height)
    }

    context.interpolationQuality = .high
    context.setAllowsAntialiasing(true)
    context.setShouldAntialias(true)
    return context
}

private func gradient(_ stops: [(CGColor, CGFloat)]) -> CGGradient {
    let colors = stops.map { $0.0 } as CFArray
    let locations = stops.map { $0.1 }
    return CGGradient(colorsSpace: colorSpace, colors: colors, locations: locations)!
}

private func drawRing(
    in context: CGContext,
    center: CGPoint,
    radius: CGFloat,
    lineWidth: CGFloat,
    progress: CGFloat,
    startAngle: CGFloat,
    tint: CGColor
) {
    context.saveGState()
    context.setLineCap(.round)
    context.setLineJoin(.round)
    context.setLineWidth(lineWidth)
    context.setStrokeColor(color(0xffffff, alpha: 0.15))
    context.addArc(
        center: center,
        radius: radius,
        startAngle: 0,
        endAngle: 2.0 * .pi,
        clockwise: false
    )
    context.strokePath()

    let start = startAngle.degreesToRadians
    let end = start + min(max(progress, 0), 1) * 2.0 * .pi

    context.saveGState()
    context.setLineCap(.round)
    context.setLineWidth(lineWidth)
    context.setShadow(offset: .zero, blur: 20, color: alpha(tint, 0.82))
    context.setStrokeColor(alpha(tint, 0.86))
    context.addArc(center: center, radius: radius, startAngle: start, endAngle: end, clockwise: false)
    context.strokePath()
    context.restoreGState()

    context.setLineCap(.round)
    context.setLineWidth(lineWidth * 0.82)
    context.setStrokeColor(tint)
    context.addArc(center: center, radius: radius, startAngle: start, endAngle: end, clockwise: false)
    context.strokePath()
    context.restoreGState()
}

private func drawReflectionGlow(in context: CGContext, center: CGPoint, tint: CGColor) {
    let widths: [CGFloat] = [108, 128, 150, 166]
    let alphas: [CGFloat] = [0.08, 0.055, 0.035, 0.018]

    for index in widths.indices {
        let width = widths[index]
        let height: CGFloat = 18 + CGFloat(index) * 8
        let yOffset = CGFloat(index) * -17
        let rect = CGRect(
            x: center.x - width / 2.0,
            y: center.y + yOffset,
            width: width,
            height: height
        )

        context.saveGState()
        context.setShadow(offset: .zero, blur: 34 + CGFloat(index) * 6, color: alpha(tint, alphas[index]))
        context.setFillColor(alpha(tint, alphas[index]))
        context.fillEllipse(in: rect)
        context.restoreGState()
    }
}

private func drawMasterIcon() throws -> CGImage {
    let context = try makeContext(width: canvasPixels, height: canvasPixels)
    let canvas = CGRect(x: 0, y: 0, width: canvasPixels, height: canvasPixels)
    context.clear(canvas)

    let iconRect = CGRect(x: 100, y: 100, width: 824, height: 824)
    let iconRadius: CGFloat = 185
    let iconPath = CGPath(roundedRect: iconRect, cornerWidth: iconRadius, cornerHeight: iconRadius, transform: nil)

    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: -24), blur: 38, color: color(0x000000, alpha: 0.46))
    context.addPath(iconPath)
    context.setFillColor(color(0x000000, alpha: 0.52))
    context.fillPath()
    context.restoreGState()

    context.saveGState()
    context.addPath(iconPath)
    context.clip()

    context.setFillColor(color(0x0a0a0c))
    context.fill(iconRect)

    let background = gradient([
        (color(0x1a1a1e), 0.0),
        (color(0x101013), 0.46),
        (color(0x0a0a0c), 1.0)
    ])
    context.drawLinearGradient(
        background,
        start: CGPoint(x: iconRect.midX, y: iconRect.maxY),
        end: CGPoint(x: iconRect.midX, y: iconRect.minY),
        options: []
    )

    let vignette = gradient([
        (color(0x303039, alpha: 0.18), 0.0),
        (color(0x151519, alpha: 0.04), 0.48),
        (color(0x000000, alpha: 0.32), 1.0)
    ])
    context.drawRadialGradient(
        vignette,
        startCenter: CGPoint(x: iconRect.midX, y: 595),
        startRadius: 24,
        endCenter: CGPoint(x: iconRect.midX, y: 595),
        endRadius: 560,
        options: [.drawsAfterEndLocation]
    )

    context.saveGState()
    context.clip(to: CGRect(x: iconRect.minX, y: iconRect.maxY - 220, width: iconRect.width, height: 220))
    let topGloss = gradient([
        (color(0xffffff, alpha: 0.12), 0.0),
        (color(0xffffff, alpha: 0.035), 0.45),
        (color(0xffffff, alpha: 0.0), 1.0)
    ])
    context.drawLinearGradient(
        topGloss,
        start: CGPoint(x: iconRect.midX, y: iconRect.maxY),
        end: CGPoint(x: iconRect.midX, y: iconRect.maxY - 220),
        options: []
    )
    context.restoreGState()

    context.saveGState()
    context.clip(to: CGRect(x: iconRect.minX, y: iconRect.maxY - 260, width: iconRect.width, height: 260))
    let topEdge = CGPath(
        roundedRect: iconRect.insetBy(dx: 1.0, dy: 1.0),
        cornerWidth: iconRadius - 1.0,
        cornerHeight: iconRadius - 1.0,
        transform: nil
    )
    context.addPath(topEdge)
    context.setStrokeColor(color(0xffffff, alpha: 0.18))
    context.setLineWidth(1.0)
    context.strokePath()
    context.restoreGState()

    let terracotta = color(0xd97757)
    let teal = color(0x10a37f)
    let azure = color(0x5a8cff)

    let pillRect = CGRect(x: 202, y: 480, width: 620, height: 184)
    let pillPath = CGPath(roundedRect: pillRect, cornerWidth: pillRect.height / 2.0, cornerHeight: pillRect.height / 2.0, transform: nil)

    let ringCenters = [
        CGPoint(x: 341, y: pillRect.midY + 1),
        CGPoint(x: 512, y: pillRect.midY + 1),
        CGPoint(x: 683, y: pillRect.midY + 1)
    ]

    drawReflectionGlow(in: context, center: CGPoint(x: ringCenters[0].x, y: pillRect.minY - 48), tint: terracotta)
    drawReflectionGlow(in: context, center: CGPoint(x: ringCenters[1].x, y: pillRect.minY - 48), tint: teal)
    drawReflectionGlow(in: context, center: CGPoint(x: ringCenters[2].x, y: pillRect.minY - 48), tint: azure)

    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: -16), blur: 30, color: color(0x000000, alpha: 0.66))
    context.addPath(pillPath)
    context.setFillColor(color(0x000000))
    context.fillPath()
    context.restoreGState()

    context.addPath(pillPath)
    context.setStrokeColor(color(0xffffff, alpha: 0.075))
    context.setLineWidth(1.25)
    context.strokePath()

    context.saveGState()
    context.clip(to: CGRect(x: pillRect.minX, y: pillRect.midY, width: pillRect.width, height: pillRect.height / 2.0))
    context.addPath(pillPath)
    context.setStrokeColor(color(0xffffff, alpha: 0.16))
    context.setLineWidth(1.0)
    context.strokePath()
    context.restoreGState()

    drawRing(
        in: context,
        center: ringCenters[0],
        radius: 48,
        lineWidth: 15,
        progress: 0.68,
        startAngle: 138,
        tint: terracotta
    )
    drawRing(
        in: context,
        center: ringCenters[1],
        radius: 50,
        lineWidth: 16,
        progress: 0.79,
        startAngle: -94,
        tint: teal
    )
    drawRing(
        in: context,
        center: ringCenters[2],
        radius: 48,
        lineWidth: 15,
        progress: 0.73,
        startAngle: 22,
        tint: azure
    )

    context.restoreGState()

    guard let image = context.makeImage() else {
        throw IconBuildError.imageCreationFailed
    }
    return image
}

private func scaledImage(from source: CGImage, pixels: Int) throws -> CGImage {
    if pixels == canvasPixels {
        return source
    }

    let context = try makeContext(width: pixels, height: pixels)
    context.clear(CGRect(x: 0, y: 0, width: pixels, height: pixels))
    context.interpolationQuality = .high
    context.draw(source, in: CGRect(x: 0, y: 0, width: pixels, height: pixels))

    guard let image = context.makeImage() else {
        throw IconBuildError.imageCreationFailed
    }
    return image
}

private func writePNG(_ image: CGImage, to url: URL) throws {
    let representation = NSBitmapImageRep(cgImage: image)
    guard let data = representation.representation(using: .png, properties: [:]) else {
        throw IconBuildError.pngEncodingFailed(url.lastPathComponent)
    }
    try data.write(to: url, options: .atomic)
}

private func iconDirectory() -> URL {
    let fileManager = FileManager.default
    let cwd = URL(fileURLWithPath: fileManager.currentDirectoryPath, isDirectory: true)
    let argument = CommandLine.arguments.first ?? "icon/make_icon.swift"
    let scriptURL = URL(fileURLWithPath: argument, relativeTo: cwd).standardizedFileURL

    if scriptURL.lastPathComponent == "make_icon.swift" {
        return scriptURL.deletingLastPathComponent()
    }
    return cwd.appendingPathComponent("icon", isDirectory: true)
}

do {
    let fileManager = FileManager.default
    let outputDirectory = iconDirectory().appendingPathComponent("AppIcon.iconset", isDirectory: true)

    if fileManager.fileExists(atPath: outputDirectory.path) {
        try fileManager.removeItem(at: outputDirectory)
    }
    try fileManager.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

    let master = try drawMasterIcon()
    let outputs: [(String, Int)] = [
        ("icon_16x16.png", 16),
        ("icon_16x16@2x.png", 32),
        ("icon_32x32.png", 32),
        ("icon_32x32@2x.png", 64),
        ("icon_128x128.png", 128),
        ("icon_128x128@2x.png", 256),
        ("icon_256x256.png", 256),
        ("icon_256x256@2x.png", 512),
        ("icon_512x512.png", 512),
        ("icon_512x512@2x.png", 1024)
    ]

    for (name, pixels) in outputs {
        let image = try scaledImage(from: master, pixels: pixels)
        try writePNG(image, to: outputDirectory.appendingPathComponent(name))
    }

    print("Wrote \(outputs.count) PNG files to \(outputDirectory.path)")
} catch {
    fputs("make_icon.swift: \(error)\n", stderr)
    exit(1)
}
