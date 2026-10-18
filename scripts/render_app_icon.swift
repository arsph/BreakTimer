// Renders the 1024 × 1024 app icon: a coffee-brown gradient with a cream budget ring and cup.
//
//     swift scripts/render_app_icon.swift BreakTimer/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png

import AppKit
import UniformTypeIdentifiers

let size = 1024.0
let cream = NSColor(srgbRed: 0.98, green: 0.94, blue: 0.88, alpha: 1)

let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil, pixelsWide: 1024, pixelsHigh: 1024, bitsPerSample: 8, samplesPerPixel: 4,
    hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
)!
let graphics = NSGraphicsContext(bitmapImageRep: rep)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = graphics
let ctx = graphics.cgContext

// Background: caramel (top left) to espresso (bottom right).
let colors = [
    NSColor(srgbRed: 0.62, green: 0.43, blue: 0.29, alpha: 1).cgColor,
    NSColor(srgbRed: 0.23, green: 0.15, blue: 0.10, alpha: 1).cgColor,
] as CFArray
let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: colors, locations: [0, 1])!
ctx.drawLinearGradient(gradient, start: CGPoint(x: 0, y: size), end: CGPoint(x: size, y: 0), options: [])

// Budget ring: faint track plus a used arc.
let center = CGPoint(x: size / 2, y: size / 2)
ctx.setLineWidth(56)
ctx.setLineCap(.round)
ctx.setStrokeColor(cream.withAlphaComponent(0.22).cgColor)
ctx.addArc(center: center, radius: 330, startAngle: 0, endAngle: .pi * 2, clockwise: false)
ctx.strokePath()
ctx.setStrokeColor(cream.cgColor)
ctx.addArc(center: center, radius: 330, startAngle: .pi / 2, endAngle: .pi / 2 - .pi * 1.35, clockwise: true)
ctx.strokePath()

// Cup in the middle.
let config = NSImage.SymbolConfiguration(pointSize: 260, weight: .medium).applying(.init(paletteColors: [cream]))
if let symbol = NSImage(systemSymbolName: "cup.and.saucer.fill", accessibilityDescription: nil)?.withSymbolConfiguration(config) {
    let s = symbol.size
    symbol.draw(in: NSRect(x: (size - s.width) / 2, y: (size - s.height) / 2, width: s.width, height: s.height))
}
NSGraphicsContext.restoreGraphicsState()

// App icons must be opaque: flatten onto an RGB context without alpha.
let flat = CGContext(
    data: nil, width: 1024, height: 1024, bitsPerComponent: 8, bytesPerRow: 0,
    space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
)!
flat.draw(rep.cgImage!, in: CGRect(x: 0, y: 0, width: 1024, height: 1024))
let output = URL(fileURLWithPath: CommandLine.arguments[1])
let destination = CGImageDestinationCreateWithURL(output as CFURL, UTType.png.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(destination, flat.makeImage()!, nil)
CGImageDestinationFinalize(destination)
