import AppKit

/// Renders a headless Finder background with matching 1× and 2× representations.
@main @MainActor
struct GenerateDMGArtwork {
    private static let canvas = NSSize(width: 680, height: 460)

    static func main() throws {
        let arguments = CommandLine.arguments
        guard arguments.count == 6 else {
            throw failure(
                "Usage: GenerateDMGArtwork <output-directory> <app-name> <display-name> <version> <brand-png>")
        }
        let output = URL(fileURLWithPath: arguments[1], isDirectory: true)
        guard let brand = NSImage(contentsOfFile: arguments[5]) else {
            throw failure("Cannot open brand image: \(arguments[5])")
        }
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

        let representations = [1, 2].map {
            render(scale: $0, appName: arguments[2], displayName: arguments[3], version: arguments[4], brand: brand)
        }
        let image = NSImage(size: canvas)
        for representation in representations { image.addRepresentation(representation) }
        guard let tiff = image.tiffRepresentation,
            let preview = representations[1].representation(using: .png, properties: [:])
        else { throw failure("Could not encode the DMG artwork.") }
        try tiff.write(to: output.appendingPathComponent("background.tiff"), options: .atomic)
        try preview.write(to: output.appendingPathComponent("background@2x.png"), options: .atomic)
        print("Rendered DMG background at 680×460 pt and 1360×920 px.")
    }

    private static func render(scale: Int, appName: String, displayName: String, version: String, brand: NSImage)
        -> NSBitmapImageRep
    {
        let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: Int(canvas.width) * scale, pixelsHigh: Int(canvas.height) * scale,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        )!
        // AppKit uses this logical size to establish the Retina scale; do not scale it a second time.
        bitmap.size = canvas
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        let context = NSGraphicsContext(bitmapImageRep: bitmap)!.cgContext
        context.translateBy(x: 0, y: canvas.height)
        context.scaleBy(x: 1, y: -1)
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: true)
        context.setAllowsAntialiasing(true)

        let paper = color(0xF6F5EF)
        let forest = color(0x23483B)
        let secondary = color(0x6D7969)
        let gold = color(0xDAB16D)
        paper.setFill()
        NSRect(origin: .zero, size: canvas).fill()

        // A quiet cover band follows the app's book-and-island identity.
        context.saveGState()
        context.clip(to: CGRect(x: 0, y: 0, width: 680, height: 128))
        gradient(
            [color(0x2D5A4A), color(0x173D32)], from: CGPoint(x: 0, y: 0),
            to: CGPoint(x: 680, y: 128), in: context)
        context.setStrokeColor(gold.withAlphaComponent(0.18).cgColor)
        context.setLineWidth(0.75)
        for offset in [0.0, 18.0, 36.0, 54.0] {
            context.move(to: CGPoint(x: 450 + offset, y: 150))
            context.addCurve(
                to: CGPoint(x: 750, y: -20 + offset),
                control1: CGPoint(x: 520 + offset, y: 18), control2: CGPoint(x: 650, y: 100 + offset))
            context.strokePath()
        }
        context.restoreGState()

        let brandRect = NSRect(x: 38, y: 29, width: 48, height: 48)
        context.saveGState()
        NSBezierPath(roundedRect: brandRect, xRadius: 12, yRadius: 12).addClip()
        brand.draw(
            in: brandRect, from: .zero, operation: .sourceOver, fraction: 1,
            respectFlipped: true, hints: nil)
        context.restoreGState()
        text(
            "\(displayName) · \(appName)", in: NSRect(x: 102, y: 29, width: 410, height: 38),
            font: .systemFont(ofSize: 25, weight: .medium), color: color(0xF5F1DF))
        text(
            "从一个词，抵达新世界。", in: NSRect(x: 40, y: 93, width: 430, height: 22),
            font: .systemFont(ofSize: 13), color: color(0xCDDAC7))

        let versionRect = NSRect(x: 550, y: 36, width: 90, height: 27)
        color(0xF5F1DF).withAlphaComponent(0.08).setFill()
        NSBezierPath(roundedRect: versionRect, xRadius: 13.5, yRadius: 13.5).fill()
        text(
            "v\(version)", in: versionRect.offsetBy(dx: 0, dy: 6),
            font: .monospacedSystemFont(ofSize: 10, weight: .medium), color: color(0xE5D0A5), alignment: .center)

        text(
            "将\(displayName)拖入 Applications 文件夹", in: NSRect(x: 40, y: 151, width: 600, height: 28),
            font: .systemFont(ofSize: 16, weight: .medium), color: forest, alignment: .center)

        // Finder places the real app and Applications icons here using dmg-settings.py.
        for x in [180.0, 500.0] {
            let halo = NSRect(x: x - 70, y: 180, width: 140, height: 140)
            color(0xFFFDF6).setFill()
            NSBezierPath(ovalIn: halo).fill()
            color(0xDCE3D3).setStroke()
            let outline = NSBezierPath(ovalIn: halo)
            outline.lineWidth = 0.8
            outline.stroke()
        }
        context.setStrokeColor(forest.withAlphaComponent(0.68).cgColor)
        context.setLineWidth(2.2)
        context.setLineCap(.round)
        context.setLineJoin(.round)
        context.move(to: CGPoint(x: 307, y: 250))
        context.addLine(to: CGPoint(x: 373, y: 250))
        context.move(to: CGPoint(x: 363, y: 240))
        context.addLine(to: CGPoint(x: 373, y: 250))
        context.addLine(to: CGPoint(x: 363, y: 260))
        context.strokePath()
        text(
            "拖动安装", in: NSRect(x: 290, y: 275, width: 100, height: 20),
            font: .systemFont(ofSize: 11), color: secondary, alignment: .center)

        context.setStrokeColor(color(0xDEE3D6).cgColor)
        context.setLineWidth(0.7)
        context.move(to: CGPoint(x: 40, y: 365))
        context.addLine(to: CGPoint(x: 640, y: 365))
        context.strokePath()
        text(
            "安装后打开\(displayName)，开始今天的学习。", in: NSRect(x: 40, y: 383, width: 600, height: 24),
            font: .systemFont(ofSize: 13), color: secondary, alignment: .center)
        text(
            "macOS 26+  ·  Apple Silicon & Intel", in: NSRect(x: 40, y: 425, width: 600, height: 18),
            font: .systemFont(ofSize: 11), color: secondary.withAlphaComponent(0.85), alignment: .center)
        return bitmap
    }

    private static func color(_ hex: UInt32) -> NSColor {
        NSColor(
            srgbRed: CGFloat((hex >> 16) & 255) / 255,
            green: CGFloat((hex >> 8) & 255) / 255, blue: CGFloat(hex & 255) / 255, alpha: 1)
    }

    private static func text(
        _ string: String, in rect: NSRect, font: NSFont, color: NSColor,
        alignment: NSTextAlignment = .left
    ) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = alignment
        paragraph.lineBreakMode = .byTruncatingTail
        NSAttributedString(
            string: string,
            attributes: [
                .font: font, .foregroundColor: color, .paragraphStyle: paragraph,
            ]
        ).draw(in: rect)
    }

    private static func gradient(_ colors: [NSColor], from start: CGPoint, to end: CGPoint, in context: CGContext) {
        let gradient = CGGradient(
            colorsSpace: CGColorSpaceCreateDeviceRGB(),
            colors: colors.map(\.cgColor) as CFArray, locations: [0, 1])!
        context.drawLinearGradient(
            gradient, start: start, end: end,
            options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
    }

    private static func failure(_ message: String) -> NSError {
        NSError(domain: "Lexisle.DMGArtwork", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }
}
