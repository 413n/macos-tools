import AppKit
import SwiftUI

/// Menu-bar template of the Narciso N mark (`Resources/logo.svg`).
///
/// A PDF representation stays sharp after display scale changes (unplugging a
/// monitor, moving the menu bar between 1x and 2x screens). Cached bitmaps do not.
enum MenuBarIcon {
    static let pointSize = NSSize(width: 18, height: 18)

    static func makeImage() -> NSImage {
        let image = NSImage(data: pdfData()) ?? rasterFallback()
        image.size = pointSize
        image.isTemplate = true
        image.cacheMode = .never
        image.accessibilityDescription = "NAF Tools"
        return image
    }

    private static func pdfData() -> Data {
        let data = NSMutableData()
        var mediaBox = CGRect(origin: .zero, size: pointSize)
        guard let consumer = CGDataConsumer(data: data as CFMutableData),
              let ctx = CGContext(consumer: consumer, mediaBox: &mediaBox, nil)
        else { return Data() }
        ctx.beginPDFPage(nil)
        drawMark(ctx, in: pointSize)
        ctx.endPDFPage()
        ctx.closePDF()
        return data as Data
    }

    private static func rasterFallback() -> NSImage {
        let image = NSImage(size: pointSize, flipped: false) { rect in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            drawMark(ctx, in: rect.size)
            return true
        }
        image.isTemplate = true
        image.cacheMode = .never
        image.accessibilityDescription = "NAF Tools"
        return image
    }

    static func drawMark(_ ctx: CGContext, in size: CGSize) {
        ctx.setShouldAntialias(true)
        ctx.interpolationQuality = .high
        let padding = size.width * 0.06
        let drawable = size.width - padding * 2
        ctx.saveGState()
        ctx.translateBy(x: padding, y: size.height - padding)
        ctx.scaleBy(x: drawable / NarcisoMark.canvas, y: -drawable / NarcisoMark.canvas)
        ctx.setFillColor(CGColor(gray: 0, alpha: 1))
        ctx.addPath(NarcisoMark.cgPath())
        ctx.fillPath()
        ctx.restoreGState()
    }
}

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

struct NarcisoN: Shape {
    func path(in rect: CGRect) -> Path {
        let sx = rect.width / NarcisoMark.canvas
        let sy = rect.height / NarcisoMark.canvas
        var transform = CGAffineTransform(a: sx, b: 0, c: 0, d: sy, tx: rect.minX, ty: rect.minY)
        return Path(NarcisoMark.cgPath().copy(using: &transform) ?? NarcisoMark.cgPath())
    }
}
