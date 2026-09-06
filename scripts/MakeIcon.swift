import AppKit
import CoreText
import Foundation

guard CommandLine.arguments.count >= 2 else {
    fputs("usage: make-icon OUT.icns [PREVIEW.png]\n", stderr)
    exit(1)
}

let icnsURL = URL(fileURLWithPath: CommandLine.arguments[1])
let previewURL = CommandLine.arguments.count >= 3 ? URL(fileURLWithPath: CommandLine.arguments[2]) : nil
let iconset = FileManager.default.temporaryDirectory.appendingPathComponent("NAFTools.iconset")
try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

/// Same geometry as `Resources/logo.svg` / `NarcisoMark`.
enum NarcisoMark {
    static let canvas: CGFloat = 500

    static func cgPath() -> CGPath {
        let path = CGMutablePath()
        path.move(to: CGPoint(x: 0, y: 0))
        path.addLine(to: CGPoint(x: 0, y: 500))
        path.addLine(to: CGPoint(x: 100.607, y: 500))
        path.addLine(to: CGPoint(x: 100.607, y: 263.5))
        path.addLine(to: CGPoint(x: 258, y: 500))
        path.addLine(to: CGPoint(x: 392, y: 500))
        path.addLine(to: CGPoint(x: 59.29, y: 0))
        path.closeSubpath()

        path.move(to: CGPoint(x: 500, y: 500))
        path.addLine(to: CGPoint(x: 500, y: 0))
        path.addLine(to: CGPoint(x: 399.393, y: 0))
        path.addLine(to: CGPoint(x: 399.393, y: 236.5))
        path.addLine(to: CGPoint(x: 242, y: 0))
        path.addLine(to: CGPoint(x: 108, y: 0))
        path.addLine(to: CGPoint(x: 440.71, y: 500))
        path.closeSubpath()
        return path
    }
}

func toolsLine(matchingWidth width: CGFloat) -> (CTLine, CGRect) {
    let fontSize = width * 0.24
    let font = NSFont.systemFont(ofSize: fontSize, weight: .black)
    let white = NSColor.white

    func makeLine(kern: CGFloat) -> CTLine {
        let styled = NSMutableAttributedString(string: "TOOLS", attributes: [
            .font: font,
            .foregroundColor: white
        ])
        if styled.length > 1 {
            styled.addAttribute(.kern, value: kern, range: NSRange(location: 0, length: styled.length - 1))
        }
        return CTLineCreateWithAttributedString(styled)
    }

    let natural = CTLineGetImageBounds(makeLine(kern: 0), nil)
    let kern = (width - natural.width) / 4
    let line = makeLine(kern: kern)
    return (line, CTLineGetImageBounds(line, nil))
}

func drawMark(_ ctx: CGContext, in rect: CGRect) {
    ctx.saveGState()
    ctx.translateBy(x: rect.minX, y: rect.maxY)
    ctx.scaleBy(x: rect.width / NarcisoMark.canvas, y: -rect.height / NarcisoMark.canvas)
    ctx.setFillColor(CGColor(gray: 1, alpha: 1))
    ctx.addPath(NarcisoMark.cgPath())
    ctx.fillPath()
    ctx.restoreGState()
}

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
    ctx.interpolationQuality = .high

    let s = CGFloat(pixels)
    let inset = s * 0.08
    let plate = CGRect(x: inset, y: inset, width: s - inset * 2, height: s - inset * 2)
    let radius = plate.width * 0.22

    let shape = CGPath(
        roundedRect: plate,
        cornerWidth: radius,
        cornerHeight: radius,
        transform: nil
    )
    ctx.setFillColor(CGColor(gray: 0, alpha: 1))
    ctx.addPath(shape)
    ctx.fillPath()

    let showWordmark = pixels >= 128
    if showWordmark {
        let logoWidth = plate.width * 0.58
        let (line, glyphs) = toolsLine(matchingWidth: logoWidth)
        let gap = logoWidth * 0.08
        let stackHeight = logoWidth + gap + glyphs.height
        let stackMinY = plate.midY - stackHeight / 2 + plate.height * 0.015
        let originX = plate.midX - logoWidth / 2
        let logoRect = CGRect(x: originX, y: stackMinY + glyphs.height + gap, width: logoWidth, height: logoWidth)
        drawMark(ctx, in: logoRect)

        ctx.saveGState()
        ctx.textPosition = CGPoint(x: originX - glyphs.minX, y: stackMinY - glyphs.minY)
        CTLineDraw(line, ctx)
        ctx.restoreGState()
    } else {
        let logoWidth = plate.width * 0.64
        let logoRect = CGRect(
            x: plate.midX - logoWidth / 2,
            y: plate.midY - logoWidth / 2,
            width: logoWidth,
            height: logoWidth
        )
        drawMark(ctx, in: logoRect)
    }

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

if let previewURL {
    try render(pixels: 512).representation(using: .png, properties: [:])!.write(to: previewURL)
}

try? FileManager.default.removeItem(at: iconset)
