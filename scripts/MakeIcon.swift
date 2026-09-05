import AppKit
import Foundation

guard CommandLine.arguments.count >= 2 else {
    fputs("usage: make-icon OUT.icns\n", stderr)
    exit(1)
}

let icnsURL = URL(fileURLWithPath: CommandLine.arguments[1])
let iconset = FileManager.default.temporaryDirectory.appendingPathComponent("NAFTools.iconset")
try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

func render(pixels: Int) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(
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
    )!
    let gc = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = gc
    let ctx = gc.cgContext
    ctx.setShouldAntialias(true)
    ctx.translateBy(x: 0, y: CGFloat(pixels))
    ctx.scaleBy(x: 1, y: -1)

    let s = CGFloat(pixels)
    let inset = s * 0.08
    let rect = CGRect(x: inset, y: inset, width: s - inset * 2, height: s - inset * 2)
    let radius = s * 0.22

    let plate = CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
    ctx.setFillColor(CGColor(red: 0.13, green: 0.11, blue: 0.09, alpha: 1))
    ctx.addPath(plate)
    ctx.fillPath()

    ctx.saveGState()
    ctx.addPath(plate)
    ctx.clip()
    let gradient = CGGradient(
        colorsSpace: CGColorSpaceCreateDeviceRGB(),
        colors: [
            CGColor(red: 0.42, green: 0.24, blue: 0.10, alpha: 0.55),
            CGColor(red: 0.10, green: 0.18, blue: 0.16, alpha: 0.35),
            CGColor(red: 0.08, green: 0.07, blue: 0.06, alpha: 0)
        ] as CFArray,
        locations: [0, 0.55, 1]
    )!
    ctx.drawLinearGradient(
        gradient,
        start: CGPoint(x: rect.minX, y: rect.maxY),
        end: CGPoint(x: rect.maxX, y: rect.minY),
        options: []
    )
    ctx.restoreGState()

    ctx.setStrokeColor(CGColor(red: 0.90, green: 0.52, blue: 0.24, alpha: 0.55))
    ctx.setLineWidth(s * 0.018)
    ctx.addPath(plate)
    ctx.strokePath()

    let copper = CGColor(red: 0.90, green: 0.52, blue: 0.24, alpha: 1)
    let shackleRect = CGRect(x: s * 0.33, y: s * 0.52, width: s * 0.34, height: s * 0.26)
    ctx.setStrokeColor(copper)
    ctx.setLineWidth(s * 0.055)
    ctx.setLineCap(.round)
    ctx.addPath(CGPath(roundedRect: shackleRect, cornerWidth: s * 0.17, cornerHeight: s * 0.17, transform: nil))
    ctx.strokePath()

    let body = CGRect(x: s * 0.28, y: s * 0.24, width: s * 0.44, height: s * 0.36)
    ctx.setFillColor(copper)
    ctx.addPath(CGPath(roundedRect: body, cornerWidth: s * 0.07, cornerHeight: s * 0.07, transform: nil))
    ctx.fillPath()

    ctx.setFillColor(CGColor(red: 0.13, green: 0.11, blue: 0.09, alpha: 1))
    ctx.fillEllipse(in: CGRect(x: s * 0.455, y: s * 0.38, width: s * 0.09, height: s * 0.09))
    ctx.fill(CGRect(x: s * 0.485, y: s * 0.28, width: s * 0.03, height: s * 0.12))

    ctx.setFillColor(CGColor(red: 0.46, green: 0.76, blue: 0.62, alpha: 1))
    let mouse = CGRect(x: s * 0.62, y: s * 0.16, width: s * 0.20, height: s * 0.24)
    ctx.addPath(CGPath(roundedRect: mouse, cornerWidth: s * 0.09, cornerHeight: s * 0.09, transform: nil))
    ctx.fillPath()
    ctx.setStrokeColor(CGColor(red: 0.10, green: 0.09, blue: 0.08, alpha: 0.55))
    ctx.setLineWidth(s * 0.012)
    ctx.move(to: CGPoint(x: mouse.midX, y: mouse.minY + s * 0.04))
    ctx.addLine(to: CGPoint(x: mouse.midX, y: mouse.midY))
    ctx.strokePath()

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

let specs: [(name: String, pixels: Int)] = [
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

for spec in specs {
    let rep = render(pixels: spec.pixels)
    let url = iconset.appendingPathComponent(spec.name)
    try rep.representation(using: .png, properties: [:])!.write(to: url)
}

let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
process.arguments = ["-c", "icns", "-o", icnsURL.path, iconset.path]
try process.run()
process.waitUntilExit()
if process.terminationStatus != 0 {
    fputs("iconutil failed\n", stderr)
    exit(1)
}
try? FileManager.default.removeItem(at: iconset)
