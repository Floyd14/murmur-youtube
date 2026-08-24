#!/usr/bin/env swift
import AppKit
import Foundation

// Icona piatta di WisperClone: pannello scuro, forma d'onda chiara e spia REC rossa.
// Nessun gradiente: la stessa grammatica visiva del registratore nell'app.
let charcoal = NSColor(srgbRed: 0.09, green: 0.085, blue: 0.075, alpha: 1)
let paper = NSColor(srgbRed: 0.88, green: 0.85, blue: 0.78, alpha: 1)
let paperMuted = NSColor(srgbRed: 0.61, green: 0.58, blue: 0.52, alpha: 1)
let record = NSColor(srgbRed: 0.78, green: 0.20, blue: 0.16, alpha: 1)
let bars: [CGFloat] = [0.34, 0.62, 1.00, 0.62, 0.34]

func drawIcon(size: CGFloat) -> NSImage {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()
    guard let context = NSGraphicsContext.current?.cgContext else {
        image.unlockFocus()
        return image
    }

    context.setShouldAntialias(true)
    context.interpolationQuality = .high

    let inset = size * 0.09
    let tile = CGRect(x: inset, y: inset, width: size - inset * 2, height: size - inset * 2)
    let radius = tile.width * 0.2237
    let shape = CGPath(roundedRect: tile, cornerWidth: radius, cornerHeight: radius, transform: nil)

    context.saveGState()
    context.setShadow(
        offset: CGSize(width: 0, height: -size * 0.012),
        blur: size * 0.035,
        color: NSColor.black.withAlphaComponent(0.34).cgColor
    )
    context.addPath(shape)
    context.setFillColor(charcoal.cgColor)
    context.fillPath()
    context.restoreGState()

    context.addPath(shape)
    context.setStrokeColor(paperMuted.withAlphaComponent(0.52).cgColor)
    context.setLineWidth(max(1, size * 0.005))
    context.strokePath()

    let barWidth = tile.width * 0.078
    let gap = tile.width * 0.055
    let totalWidth = CGFloat(bars.count) * barWidth + CGFloat(bars.count - 1) * gap
    let maxHeight = tile.height * 0.44
    var x = tile.midX - totalWidth / 2

    context.setFillColor(paper.cgColor)
    for bar in bars {
        let height = max(barWidth, maxHeight * bar)
        let rect = CGRect(x: x, y: tile.midY - height / 2, width: barWidth, height: height)
        context.addPath(CGPath(
            roundedRect: rect,
            cornerWidth: barWidth / 2,
            cornerHeight: barWidth / 2,
            transform: nil
        ))
        context.fillPath()
        x += barWidth + gap
    }

    let dotSize = tile.width * 0.105
    let dot = CGRect(
        x: tile.maxX - tile.width * 0.18 - dotSize,
        y: tile.maxY - tile.height * 0.18 - dotSize,
        width: dotSize,
        height: dotSize
    )
    context.setFillColor(record.cgColor)
    context.fillEllipse(in: dot)

    image.unlockFocus()
    return image
}

func png(pixels: Int) -> Data? {
    guard let representation = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: pixels,
        pixelsHigh: pixels,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ) else { return nil }

    representation.size = NSSize(width: pixels, height: pixels)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: representation)
    drawIcon(size: CGFloat(pixels)).draw(
        in: NSRect(x: 0, y: 0, width: pixels, height: pixels),
        from: .zero,
        operation: .sourceOver,
        fraction: 1
    )
    NSGraphicsContext.restoreGraphicsState()
    return representation.representation(using: .png, properties: [:])
}

let fileManager = FileManager.default
let root = URL(fileURLWithPath: fileManager.currentDirectoryPath)
let iconset = root.appendingPathComponent("Resources/AppIcon.iconset")
try? fileManager.removeItem(at: iconset)
try fileManager.createDirectory(at: iconset, withIntermediateDirectories: true)

let variants: [(points: Int, scale: Int)] = [
    (16, 1), (16, 2), (32, 1), (32, 2), (128, 1),
    (128, 2), (256, 1), (256, 2), (512, 1), (512, 2),
]

for variant in variants {
    let pixels = variant.points * variant.scale
    guard let data = png(pixels: pixels) else {
        print("Impossibile generare l'icona da \(pixels) px")
        exit(1)
    }

    let suffix = variant.scale == 2 ? "@2x" : ""
    let name = "icon_\(variant.points)x\(variant.points)\(suffix).png"
    try data.write(to: iconset.appendingPathComponent(name))
}

print("Generate \(variants.count) icone in Resources/AppIcon.iconset")
