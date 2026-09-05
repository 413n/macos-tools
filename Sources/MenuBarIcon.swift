import AppKit
import SwiftUI

enum MenuBarDisplay: String, CaseIterable, Identifiable {
    case logoOnly
    case activeIcons
    case logoAndActive

    var id: String { rawValue }

    var title: String {
        switch self {
        case .logoOnly: "Logo only"
        case .activeIcons: "Active icons"
        case .logoAndActive: "Logo and active icons"
        }
    }
}

enum MenuBarTool: String, CaseIterable {
    case keyboard
    case scroll
    case lid
    case awake

    var title: String {
        switch self {
        case .keyboard: "Keyboard"
        case .scroll: "Scroll"
        case .lid: "Lid Sleep"
        case .awake: "Awake"
        }
    }

    var systemImage: String {
        switch self {
        case .keyboard: "lock.fill"
        case .scroll: "computermouse.fill"
        case .lid: "moon.zzz.fill"
        case .awake: "cup.and.saucer.fill"
        }
    }

    var opticalNudge: CGSize {
        switch self {
        case .keyboard: CGSize(width: 0.5, height: 0)
        default: .zero
        }
    }
}

/// Menu-bar template of the Narciso N mark, optionally followed by active-tool symbols.
///
/// A PDF representation stays sharp after display scale changes (unplugging a
/// monitor, moving the menu bar between 1x and 2x screens). Cached bitmaps do not.
enum MenuBarIcon {
    static let pointSize = NSSize(width: 18, height: 18)
    /// Two rows of tiny glyphs, filling a column then growing to the right.
    private static let gridCell: CGFloat = 8
    private static let gridGap: CGFloat = 2
    private static let logoToGridGap: CGFloat = 4
    private static let symbolPointSize: CGFloat = 8

    static func makeImage(mode: MenuBarDisplay, tools: [MenuBarTool]) -> NSImage {
        switch mode {
        case .logoOnly:
            return makeLogoImage()
        case .activeIcons:
            return tools.isEmpty ? makeLogoImage() : makeCompositeImage(showLogo: false, tools: tools)
        case .logoAndActive:
            return tools.isEmpty ? makeLogoImage() : makeCompositeImage(showLogo: true, tools: tools)
        }
    }

    static func statusItemLength(mode: MenuBarDisplay, tools: [MenuBarTool]) -> CGFloat {
        if mode == .logoOnly || tools.isEmpty {
            return NSStatusItem.squareLength
        }
        return NSStatusItem.variableLength
    }

    static func tooltip(tools: [MenuBarTool]) -> String {
        if tools.isEmpty { return "NAF Tools" }
        return "NAF Tools — \(tools.map(\.title).joined(separator: ", "))"
    }

    private static func makeLogoImage() -> NSImage {
        let image = NSImage(data: pdfData()) ?? rasterFallback()
        image.size = pointSize
        image.isTemplate = true
        image.cacheMode = .never
        image.accessibilityDescription = "NAF Tools"
        return image
    }

    private static func gridSize(toolCount: Int) -> NSSize {
        let columns = (toolCount + 1) / 2
        let width = CGFloat(columns) * gridCell + CGFloat(max(0, columns - 1)) * gridGap
        return NSSize(width: width, height: pointSize.height)
    }

    private static func makeCompositeImage(showLogo: Bool, tools: [MenuBarTool]) -> NSImage {
        let grid = gridSize(toolCount: tools.count)
        let size = NSSize(
            width: showLogo ? pointSize.width + logoToGridGap + grid.width : grid.width,
            height: pointSize.height
        )
        let image = NSImage(size: size, flipped: false) { rect in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            ctx.setShouldAntialias(true)
            ctx.interpolationQuality = .high
            var originX: CGFloat = 0
            if showLogo {
                drawMark(ctx, in: pointSize)
                originX = pointSize.width + logoToGridGap
            }
            for (index, tool) in tools.enumerated() {
                let col = index / 2
                let isTop = index % 2 == 0
                let frame = CGRect(
                    x: originX + CGFloat(col) * (gridCell + gridGap),
                    y: isTop ? gridCell + gridGap : 0,
                    width: gridCell,
                    height: gridCell
                )
                drawSymbol(tool, in: frame)
            }
            return true
        }
        image.isTemplate = true
        image.cacheMode = .never
        image.accessibilityDescription = "NAF Tools"
        return image
    }

    private static func drawSymbol(_ tool: MenuBarTool, in rect: CGRect) {
        let config = NSImage.SymbolConfiguration(pointSize: symbolPointSize, weight: .semibold)
            .applying(NSImage.SymbolConfiguration(paletteColors: [.black]))
        guard let symbol = NSImage(systemSymbolName: tool.systemImage, accessibilityDescription: nil)?
            .withSymbolConfiguration(config)
        else { return }
        let size = symbol.size
        let dest = NSRect(
            x: rect.midX - size.width / 2 + tool.opticalNudge.width * 0.4,
            y: rect.midY - size.height / 2 + tool.opticalNudge.height * 0.4,
            width: size.width,
            height: size.height
        )
        symbol.draw(in: dest, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
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
