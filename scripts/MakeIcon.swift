import AppKit
import Foundation

guard CommandLine.arguments.count >= 2 else {
    fputs("usage: make-icon OUT.icns [PREVIEW.png]\n", stderr)
    exit(1)
}

let icnsURL = URL(fileURLWithPath: CommandLine.arguments[1])
let previewURL = CommandLine.arguments.count >= 3 ? URL(fileURLWithPath: CommandLine.arguments[2]) : nil
let iconset = FileManager.default.temporaryDirectory.appendingPathComponent("Yeobun.iconset")
try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

/// Native renderer for the canonical vector master in `Resources/AppIcon.svg`.
enum AppWrenchMark {
    static let canvas: CGFloat = 1024
    static let scale: CGFloat = 0.82
    static let placement = CGAffineTransform(
        a: scale,
        b: 0,
        c: 0,
        d: scale,
        tx: 512 - 512 * scale,
        ty: 520 - 512 * scale
    )

    static func silhouette() -> CGPath {
        let path = CGMutablePath()
        path.move(to: CGPoint(x: 128, y: 140))
        path.addLine(to: CGPoint(x: 298, y: 140))
        path.addLine(to: CGPoint(x: 420, y: 360))
        path.addLine(to: CGPoint(x: 604, y: 360))
        path.addLine(to: CGPoint(x: 726, y: 140))
        path.addLine(to: CGPoint(x: 896, y: 140))
        path.addLine(to: CGPoint(x: 820, y: 420))
        path.addLine(to: CGPoint(x: 640, y: 540))
        path.addLine(to: CGPoint(x: 640, y: 830))
        path.addCurve(
            to: CGPoint(x: 512, y: 902),
            control1: CGPoint(x: 640, y: 876),
            control2: CGPoint(x: 602.7, y: 902)
        )
        path.addCurve(
            to: CGPoint(x: 384, y: 830),
            control1: CGPoint(x: 421.3, y: 902),
            control2: CGPoint(x: 384, y: 876)
        )
        path.addLine(to: CGPoint(x: 384, y: 540))
        path.addLine(to: CGPoint(x: 204, y: 420))
        path.closeSubpath()
        return path
    }

    static func handle() -> CGPath {
        let path = CGMutablePath()
        path.move(to: CGPoint(x: 384, y: 425))
        path.addLine(to: CGPoint(x: 640, y: 425))
        path.addLine(to: CGPoint(x: 640, y: 830))
        path.addCurve(
            to: CGPoint(x: 512, y: 902),
            control1: CGPoint(x: 640, y: 876),
            control2: CGPoint(x: 602.7, y: 902)
        )
        path.addCurve(
            to: CGPoint(x: 384, y: 830),
            control1: CGPoint(x: 421.3, y: 902),
            control2: CGPoint(x: 384, y: 876)
        )
        path.closeSubpath()
        return path
    }

    static func joint() -> CGPath {
        let path = CGMutablePath()
        path.move(to: CGPoint(x: 420, y: 360))
        path.addLine(to: CGPoint(x: 604, y: 360))
        path.addLine(to: CGPoint(x: 640, y: 425))
        path.addLine(to: CGPoint(x: 384, y: 425))
        path.closeSubpath()
        return path
    }

    static func placedHole() -> CGPath {
        var transform = placement
        let hole = CGPath(ellipseIn: CGRect(x: 467, y: 755, width: 90, height: 90), transform: nil)
        return hole.copy(using: &transform) ?? hole
    }
}

func rgb(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat) -> CGColor {
    CGColor(red: red / 255, green: green / 255, blue: blue / 255, alpha: 1)
}

func rgba(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat, _ alpha: CGFloat) -> CGColor {
    CGColor(red: red / 255, green: green / 255, blue: blue / 255, alpha: alpha)
}

func drawGradient(
    _ ctx: CGContext,
    clippedTo path: CGPath,
    colors: [CGColor],
    locations: [CGFloat]? = nil,
    start: CGPoint,
    end: CGPoint
) {
    guard let gradient = CGGradient(
        colorsSpace: CGColorSpaceCreateDeviceRGB(),
        colors: colors as CFArray,
        locations: locations
    ) else { return }
    ctx.saveGState()
    ctx.addPath(path)
    ctx.clip()
    ctx.drawLinearGradient(gradient, start: start, end: end, options: [])
    ctx.restoreGState()
}

func drawRadialGradient(
    _ ctx: CGContext,
    clippedTo path: CGPath,
    colors: [CGColor],
    startCenter: CGPoint,
    startRadius: CGFloat,
    endCenter: CGPoint,
    endRadius: CGFloat
) {
    guard let gradient = CGGradient(
        colorsSpace: CGColorSpaceCreateDeviceRGB(),
        colors: colors as CFArray,
        locations: [0, 1]
    ) else { return }
    ctx.saveGState()
    ctx.addPath(path)
    ctx.clip()
    ctx.drawRadialGradient(
        gradient,
        startCenter: startCenter,
        startRadius: startRadius,
        endCenter: endCenter,
        endRadius: endRadius,
        options: []
    )
    ctx.restoreGState()
}

func drawAppIcon(_ ctx: CGContext, pixels: CGFloat) {
    ctx.saveGState()
    ctx.translateBy(x: 0, y: pixels)
    ctx.scaleBy(x: pixels / AppWrenchMark.canvas, y: -pixels / AppWrenchMark.canvas)

    let plate = CGPath(
        roundedRect: CGRect(x: 64, y: 64, width: 896, height: 896),
        cornerWidth: 205,
        cornerHeight: 205,
        transform: nil
    )
    drawGradient(
        ctx,
        clippedTo: plate,
        colors: [rgb(41, 46, 53), rgb(19, 23, 28), rgb(5, 6, 7)],
        locations: [0, 0.5, 1],
        start: CGPoint(x: 154, y: 104),
        end: CGPoint(x: 870, y: 938)
    )
    drawRadialGradient(
        ctx,
        clippedTo: plate,
        colors: [rgba(139, 153, 168, 0.2), rgba(139, 153, 168, 0)],
        startCenter: CGPoint(x: 420, y: 245),
        startRadius: 0,
        endCenter: CGPoint(x: 420, y: 245),
        endRadius: 655
    )

    ctx.saveGState()
    ctx.concatenate(AppWrenchMark.placement)
    let silhouette = AppWrenchMark.silhouette()

    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -30), blur: 30, color: rgba(0, 0, 0, 0.62))
    ctx.setFillColor(rgba(0, 0, 0, 0.28))
    ctx.addPath(silhouette)
    ctx.fillPath()
    ctx.restoreGState()

    drawGradient(
        ctx,
        clippedTo: silhouette,
        colors: [rgb(168, 207, 208), rgb(242, 233, 221), rgb(211, 199, 222), rgb(231, 240, 235), rgb(145, 181, 194)],
        locations: [0, 0.25, 0.48, 0.7, 1],
        start: CGPoint(x: 128, y: 185),
        end: CGPoint(x: 896, y: 385)
    )

    ctx.setStrokeColor(rgba(233, 240, 238, 0.42))
    ctx.setLineWidth(18)
    ctx.setLineJoin(.round)
    ctx.addPath(silhouette)
    ctx.strokePath()

    drawGradient(
        ctx,
        clippedTo: AppWrenchMark.handle(),
        colors: [rgb(238, 231, 220), rgb(168, 186, 198), rgb(200, 181, 208), rgb(235, 220, 197)],
        locations: [0, 0.38, 0.68, 1],
        start: CGPoint(x: 470, y: 410),
        end: CGPoint(x: 565, y: 900)
    )

    ctx.setFillColor(rgb(216, 214, 223))
    ctx.addPath(AppWrenchMark.joint())
    ctx.fillPath()

    drawGradient(
        ctx,
        clippedTo: silhouette,
        colors: [rgba(255, 255, 255, 0.12), rgba(255, 255, 255, 0)],
        start: CGPoint(x: 300, y: 135),
        end: CGPoint(x: 610, y: 900)
    )
    ctx.restoreGState()

    let placedHole = AppWrenchMark.placedHole()
    drawGradient(
        ctx,
        clippedTo: placedHole,
        colors: [rgb(41, 46, 53), rgb(19, 23, 28), rgb(5, 6, 7)],
        locations: [0, 0.5, 1],
        start: CGPoint(x: 154, y: 104),
        end: CGPoint(x: 870, y: 938)
    )
    drawRadialGradient(
        ctx,
        clippedTo: placedHole,
        colors: [rgba(139, 153, 168, 0.2), rgba(139, 153, 168, 0)],
        startCenter: CGPoint(x: 420, y: 245),
        startRadius: 0,
        endCenter: CGPoint(x: 420, y: 245),
        endRadius: 655
    )
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

    drawAppIcon(ctx, pixels: CGFloat(pixels))

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
