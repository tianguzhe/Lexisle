import CoreGraphics
import CoreText
import Foundation
import ImageIO
import UniformTypeIdentifiers

// One vector master supplies the app icon, in-app PDF mark, SVG exports and brand preview.
let root = URL(
    fileURLWithPath: CommandLine.arguments.count > 1
        ? CommandLine.arguments[1] : FileManager.default.currentDirectoryPath)
let assets = root.appendingPathComponent("App/Resources/Assets.xcassets")
let iconFolder = assets.appendingPathComponent("AppIcon.appiconset")
let markFolder = assets.appendingPathComponent("BrandMark.imageset")
let outputFolder = root.appendingPathComponent("Documentation/Brand")
for folder in [iconFolder, markFolder, outputFolder] {
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
}

struct Ink {
    let hex: UInt32
    var color: CGColor {
        CGColor(
            red: CGFloat((hex >> 16) & 255) / 255,
            green: CGFloat((hex >> 8) & 255) / 255,
            blue: CGFloat(hex & 255) / 255, alpha: 1)
    }
    var svg: String { String(format: "#%06X", hex) }
}

struct Palette {
    let top: Ink
    let bottom: Ink
    let paper: Ink
    let sun: Ink
    static let standard = Palette(
        top: Ink(hex: 0x2C6051), bottom: Ink(hex: 0x163E34),
        paper: Ink(hex: 0xF5F1DF), sun: Ink(hex: 0xDCB16E))
    static let dark = Palette(
        top: Ink(hex: 0x183F34), bottom: Ink(hex: 0x0B211C),
        paper: Ink(hex: 0xF0EBD5), sun: Ink(hex: 0xD5A967))
    static let tinted = Palette(
        top: Ink(hex: 0x393939), bottom: Ink(hex: 0x171717),
        paper: Ink(hex: 0xF1F1F1), sun: Ink(hex: 0xBBBBBB))
}

enum Segment {
    case move(CGFloat, CGFloat)
    case line(CGFloat, CGFloat)
    case curve(CGFloat, CGFloat, CGFloat, CGFloat, CGFloat, CGFloat)
    case close
}

struct VectorPath {
    let segments: [Segment]

    var cgPath: CGPath {
        let path = CGMutablePath()
        for segment in segments {
            switch segment {
            case .move(let x, let y): path.move(to: CGPoint(x: x, y: y))
            case .line(let x, let y): path.addLine(to: CGPoint(x: x, y: y))
            case .curve(let x1, let y1, let x2, let y2, let x, let y):
                path.addCurve(to: CGPoint(x: x, y: y), control1: CGPoint(x: x1, y: y1), control2: CGPoint(x: x2, y: y2))
            case .close: path.closeSubpath()
            }
        }
        return path
    }

    var svg: String {
        segments.map { segment in
            switch segment {
            case .move(let x, let y): "M\(x),\(y)"
            case .line(let x, let y): "L\(x),\(y)"
            case .curve(let x1, let y1, let x2, let y2, let x, let y):
                "C\(x1),\(y1) \(x2),\(y2) \(x),\(y)"
            case .close: "Z"
            }
        }.joined(separator: " ")
    }
}

// An asymmetric open page becomes an island. Its curved cut-out is a bay and a book's spine.
let island = VectorPath(segments: [
    .move(256, 600), .line(256, 384),
    .curve(256, 362, 273, 348, 294, 355),
    .curve(385, 382, 451, 424, 501, 486),
    .curve(528, 557, 519, 646, 478, 720),
    .curve(392, 718, 315, 687, 267, 642),
    .curve(260, 635, 256, 617, 256, 600), .close,
    .move(536, 472),
    .curve(585, 392, 650, 320, 731, 265),
    .curve(754, 253, 777, 272, 768, 296),
    .curve(721, 414, 677, 531, 636, 641),
    .curve(622, 678, 586, 706, 548, 716),
    .curve(539, 718, 529, 720, 517, 722),
    .curve(556, 643, 563, 553, 536, 472), .close,
])

func drawSymbol(_ context: CGContext, palette: Palette) {
    context.saveGState()
    context.translateBy(x: 512, y: 512)
    context.scaleBy(x: 1.24, y: 1.24)
    context.translateBy(x: -512, y: -494)
    context.addPath(island.cgPath)
    context.setFillColor(palette.paper.color)
    context.fillPath()
    context.setFillColor(palette.sun.color)
    context.fillEllipse(in: CGRect(x: 302, y: 243, width: 86, height: 86))
    context.restoreGState()
}

func drawLogo(_ context: CGContext, in rect: CGRect, palette: Palette, radius: CGFloat = 0) {
    context.saveGState()
    context.addPath(CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil))
    context.clip()
    context.translateBy(x: rect.minX, y: rect.maxY)
    context.scaleBy(x: rect.width / 1024, y: -rect.height / 1024)
    let gradient = CGGradient(
        colorsSpace: CGColorSpaceCreateDeviceRGB(),
        colors: [palette.top.color, palette.bottom.color] as CFArray,
        locations: [0, 1])!
    context.drawLinearGradient(
        gradient, start: CGPoint(x: 0, y: 0), end: CGPoint(x: 820, y: 1024),
        options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
    drawSymbol(context, palette: palette)
    context.restoreGState()
}

func bitmap(width: Int, height: Int, alpha: Bool = false) -> CGContext {
    CGContext(
        data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: alpha ? CGImageAlphaInfo.premultipliedLast.rawValue : CGImageAlphaInfo.noneSkipLast.rawValue)!
}

func writePNG(_ context: CGContext, to url: URL) throws {
    let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(destination, context.makeImage()!, nil)
    guard CGImageDestinationFinalize(destination) else { throw CocoaError(.fileWriteUnknown) }
}

func renderIcon(size: Int, filename: String, palette: Palette = .standard, mac: Bool = false) throws {
    let context = bitmap(width: size, height: size, alpha: mac)
    context.scaleBy(x: CGFloat(size) / 1024, y: CGFloat(size) / 1024)
    if mac {
        let face = CGRect(x: 96, y: 96, width: 832, height: 832)
        context.saveGState()
        context.setShadow(
            offset: CGSize(width: 0, height: -12), blur: 24,
            color: CGColor(red: 0, green: 0, blue: 0, alpha: 0.18))
        context.addPath(CGPath(roundedRect: face, cornerWidth: 186, cornerHeight: 186, transform: nil))
        context.setFillColor(palette.bottom.color)
        context.fillPath()
        context.restoreGState()
        drawLogo(context, in: face, palette: palette, radius: 186)
    } else {
        drawLogo(context, in: CGRect(x: 0, y: 0, width: 1024, height: 1024), palette: palette)
    }
    try writePNG(context, to: iconFolder.appendingPathComponent(filename))
}

var images: [[String: Any]] = []
for (name, palette) in [("Default", Palette.standard), ("Dark", .dark), ("Tinted", .tinted)] {
    let filename = "AppIcon-\(name).png"
    try renderIcon(size: 1024, filename: filename, palette: palette)
    var entry: [String: Any] = ["idiom": "universal", "platform": "ios", "size": "1024x1024", "filename": filename]
    if name != "Default" { entry["appearances"] = [["appearance": "luminosity", "value": name.lowercased()]] }
    images.append(entry)
}
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let filename = "AppIcon-mac-\(size)@\(scale)x.png"
        try renderIcon(size: size * scale, filename: filename, mac: true)
        images.append(["idiom": "mac", "size": "\(size)x\(size)", "scale": "\(scale)x", "filename": filename])
    }
}
let iconManifest: [String: Any] = ["images": images, "info": ["author": "xcode", "version": 1]]
try JSONSerialization.data(withJSONObject: iconManifest, options: [.prettyPrinted, .sortedKeys])
    .write(to: iconFolder.appendingPathComponent("Contents.json"))

var mediaBox = CGRect(x: 0, y: 0, width: 1024, height: 1024)
let pdf = CGContext(markFolder.appendingPathComponent("BrandMark.pdf") as CFURL, mediaBox: &mediaBox, nil)!
pdf.beginPDFPage(nil)
drawLogo(pdf, in: mediaBox, palette: .standard)
pdf.endPDFPage()
pdf.closePDF()
let markManifest: [String: Any] = [
    "images": [["filename": "BrandMark.pdf", "idiom": "universal"]],
    "info": ["author": "xcode", "version": 1],
    "properties": ["preserves-vector-representation": true, "template-rendering-intent": "original"],
]
try JSONSerialization.data(withJSONObject: markManifest, options: [.prettyPrinted, .sortedKeys])
    .write(to: markFolder.appendingPathComponent("Contents.json"))

let symbolSVG = """
    <g transform="translate(512 512) scale(1.24) translate(-512 -494)">
      <path d="\(island.svg)" fill="\(Palette.standard.paper.svg)"/>
      <circle cx="345" cy="286" r="43" fill="\(Palette.standard.sun.svg)"/>
    </g>
    """
let logoSVG = """
    <svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 1024 1024" role="img" aria-label="词屿 Lexisle">
    <defs><linearGradient id="jade" x1="0" y1="0" x2="0.8" y2="1"><stop stop-color="\(Palette.standard.top.svg)"/><stop offset="1" stop-color="\(Palette.standard.bottom.svg)"/></linearGradient></defs>
    <rect width="1024" height="1024" rx="224" fill="url(#jade)"/>
    \(symbolSVG)
    </svg>
    """
try logoSVG.write(to: outputFolder.appendingPathComponent("lexisle-logo.svg"), atomically: true, encoding: .utf8)
let standalone = """
    <svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 1024 1024" role="img" aria-label="词屿符号">
    \(symbolSVG.replacingOccurrences(of: Palette.standard.paper.svg, with: "#244F42").replacingOccurrences(of: Palette.standard.sun.svg, with: "#244F42"))
    </svg>
    """
try standalone.write(to: outputFolder.appendingPathComponent("lexisle-symbol.svg"), atomically: true, encoding: .utf8)
let logoPreview = bitmap(width: 1024, height: 1024, alpha: true)
drawLogo(logoPreview, in: mediaBox, palette: .standard, radius: 224)
try writePNG(logoPreview, to: outputFolder.appendingPathComponent("lexisle-logo.png"))

func drawText(
    _ text: String, font: String, size: CGFloat, color: Ink, x: CGFloat, y: CGFloat, tracking: CGFloat = 0,
    in context: CGContext
) {
    let attributes: [NSAttributedString.Key: Any] = [
        NSAttributedString.Key(kCTFontAttributeName as String): CTFontCreateWithName(font as CFString, size, nil),
        NSAttributedString.Key(kCTForegroundColorAttributeName as String): color.color,
        NSAttributedString.Key(kCTKernAttributeName as String): tracking,
    ]
    context.textPosition = CGPoint(x: x, y: y)
    CTLineDraw(CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attributes)), context)
}

let board = bitmap(width: 1440, height: 900)
board.setFillColor(Ink(hex: 0xF4F3EC).color)
board.fill(CGRect(x: 0, y: 0, width: 1440, height: 900))
let ink = Ink(hex: 0x23483B)
let secondary = Ink(hex: 0x738172)
drawText(
    "LEXISLE   /   BRAND IDENTITY", font: "Menlo-Regular", size: 14, color: secondary, x: 86, y: 818, tracking: 1,
    in: board)
drawLogo(board, in: CGRect(x: 86, y: 306, width: 390, height: 390), palette: .standard, radius: 88)
drawText("词屿", font: "PingFangSC-Medium", size: 91, color: ink, x: 560, y: 597, tracking: 9, in: board)
drawText("Lexisle", font: "Georgia", size: 68, color: ink, x: 564, y: 507, tracking: -1, in: board)
drawText("从一个词，抵达新世界。", font: "PingFangSC-Regular", size: 25, color: secondary, x: 567, y: 433, in: board)
board.setStrokeColor(Ink(hex: 0xD9DED0).color)
board.setLineWidth(1)
board.move(to: CGPoint(x: 86, y: 246))
board.addLine(to: CGPoint(x: 1354, y: 246))
board.strokePath()
drawText("清晰于每一种尺寸", font: "PingFangSC-Regular", size: 16, color: secondary, x: 86, y: 199, in: board)
for (index, size) in [80, 56, 40, 24].enumerated() {
    let x = CGFloat(86 + index * 115)
    drawLogo(
        board, in: CGRect(x: x, y: 83, width: CGFloat(size), height: CGFloat(size)), palette: .standard,
        radius: CGFloat(size) * 0.23)
}
for (index, item) in [("松绿", Ink(hex: 0x244F42)), ("纸白", Ink(hex: 0xF5F1DF)), ("暖日", Ink(hex: 0xDCB16E))].enumerated() {
    let x = CGFloat(790 + index * 180)
    board.setFillColor(item.1.color)
    board.fillEllipse(in: CGRect(x: x, y: 122, width: 38, height: 38))
    drawText(item.0, font: "PingFangSC-Regular", size: 16, color: secondary, x: x, y: 88, in: board)
}
try writePNG(board, to: outputFolder.appendingPathComponent("brand-preview.png"))
print("Generated Lexisle vector logo, PDF mark, iOS appearance icons and all macOS icon sizes.")
