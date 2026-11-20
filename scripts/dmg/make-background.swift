// Renders the DMG window background (violet, large faint app icon, golden vein arrow to Applications).
//   swift scripts/dmg/make-background.swift <AppIcon.png> <out-dir>   → background.png, background@2x.png
// Layout (points, top-left origin) must match scripts/release.sh: window 660×430, icons at (165,180) and (495,180).
import AppKit

let size = CGSize(width: 660, height: 430)
let appCenter = CGPoint(x: 165, y: 180)
let applicationsCenter = CGPoint(x: 495, y: 180)

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(
        srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
        blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}

func cubic(_ p0: CGPoint, _ p1: CGPoint, _ p2: CGPoint, _ p3: CGPoint, _ t: CGFloat) -> CGPoint {
    let u = 1 - t
    let a = u * u * u, b = 3 * u * u * t, c = 3 * u * t * t, d = t * t * t
    return CGPoint(x: a * p0.x + b * p1.x + c * p2.x + d * p3.x, y: a * p0.y + b * p1.y + c * p2.y + d * p3.y)
}

/// The main vein's curve (points, top-left origin).
let veinStart = CGPoint(x: 236, y: 196)
let veinControl1 = CGPoint(x: 262, y: 92)
let veinControl2 = CGPoint(x: 372, y: 64)
let veinTip = CGPoint(x: 420, y: 160)

func veinPoint(_ t: CGFloat) -> CGPoint { cubic(veinStart, veinControl1, veinControl2, veinTip, t) }

/// The vein as a path.
func veinPath() -> CGPath {
    let path = CGMutablePath()
    path.move(to: veinStart)
    path.addCurve(to: veinTip, control1: veinControl1, control2: veinControl2)
    return path
}

/// Strokes `path` with gold that brightens from the start toward the tip.
func strokeGold(_ context: CGContext, _ path: CGPath, width: CGFloat, from: CGFloat = 0.7) {
    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    let gold = CGGradient(
        colorsSpace: space,
        colors: [color(0xF2D27A, from), color(0xF5DC8E, 0.95), color(0xFFEDB8, 1)] as CFArray,
        locations: [0, 0.6, 1])!
    context.saveGState()
    context.addPath(path)
    context.setLineWidth(width)
    context.setLineCap(.round)
    context.setLineJoin(.round)
    context.replacePathWithStrokedPath()
    context.clip()
    context.drawLinearGradient(
        gold, start: veinStart, end: veinTip, options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
    context.restoreGState()
}

func drawVeinArrow(_ context: CGContext) {
    context.saveGState()
    // The soft golden shimmer the icon's veins have.
    context.setShadow(offset: .zero, blur: 10, color: color(0xF2D27A, 0.6))
    context.beginTransparencyLayer(auxiliaryInfo: nil)
        strokeGold(context, veinPath(), width: 2.6)
    // Slim open arrowhead along the arriving direction.
    let arriving = atan2(veinTip.y - veinPoint(0.94).y, veinTip.x - veinPoint(0.94).x)
    let head = CGMutablePath()
    for side in [-1.0, 1.0] {
        let angle = arriving + .pi + side * 0.5
        head.move(to: veinTip)
        head.addLine(to: CGPoint(x: veinTip.x + cos(angle) * 19, y: veinTip.y + sin(angle) * 19))
    }
    strokeGold(context, head, width: 2.6, from: 1)
    context.endTransparencyLayer()
    context.restoreGState()
}

/// White in the middle, fading to black at the edges (alpha mask for the faint icon).
func softMask() -> CGImage? {
    let side = 256
    guard
        let context = CGContext(
            data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side,
            space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue)
    else { return nil }
    let gradient = CGGradient(
        colorsSpace: CGColorSpaceCreateDeviceGray(),
        colors: [CGColor(gray: 1, alpha: 1), CGColor(gray: 1, alpha: 1), CGColor(gray: 0, alpha: 1)] as CFArray,
        locations: [0, 0.45, 1])!
    let center = CGPoint(x: side / 2, y: side / 2)
    context.drawRadialGradient(
        gradient, startCenter: center, startRadius: 0, endCenter: center, endRadius: CGFloat(side) / 2, options: [])
    return context.makeImage()
}

func render(scale: CGFloat, icon: NSImage) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: Int(size.width * scale), pixelsHigh: Int(size.height * scale),
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
        bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = size
    let graphics = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.current = graphics
    let context = graphics.cgContext  // already scaled to points (`rep.size`)
    context.translateBy(x: 0, y: size.height)
    context.scaleBy(x: 1, y: -1)  // top-left origin like Finder

    // Violet night sky: radial glow from the upper left.
    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    let sky = CGGradient(
        colorsSpace: space, colors: [color(0x4A2A8C), color(0x2A1656), color(0x140A2C)] as CFArray,
        locations: [0, 0.55, 1])!
    context.drawRadialGradient(
        sky, startCenter: CGPoint(x: 140, y: 40), startRadius: 0, endCenter: CGPoint(x: 200, y: 120),
        endRadius: 640, options: [.drawsAfterEndLocation])

    // The app icon, large and faint, drifting off the right edge; its square edges fade out.
    if let cgIcon = icon.cgImage(forProposedRect: nil, context: nil, hints: nil), let mask = softMask() {
        context.saveGState()
        context.clip(to: CGRect(x: 300, y: -110, width: 520, height: 520), mask: mask)
        context.setAlpha(0.16)
        context.translateBy(x: 560, y: 150)
        context.rotate(by: -0.2)
        context.scaleBy(x: 1, y: -1)
        context.draw(cgIcon, in: CGRect(x: -260, y: -260, width: 520, height: 520))
        context.restoreGState()
    }

    // Soft light pools under the icons; mid-violet so Finder's labels read in light (black) and dark (white).
    for center in [appCenter, applicationsCenter] {
        let pool = CGGradient(
            colorsSpace: space, colors: [color(0xB79CF0, 0.32), color(0xB79CF0, 0)] as CFArray, locations: [0, 1])!
        context.drawRadialGradient(
            pool, startCenter: center, startRadius: 0, endCenter: center, endRadius: 105, options: [])
        let label = CGRect(x: center.x - 64, y: center.y + 72, width: 128, height: 24)
        context.addPath(CGPath(roundedRect: label, cornerWidth: 12, cornerHeight: 12, transform: nil))
        context.setFillColor(color(0x8466CC, 0.95))
        context.fillPath()
    }

    // A golden vein arcing from the app to Applications, drawn like the veins in the app icon: one fine line
    // ending in a slim open arrowhead.
    drawVeinArrow(context)

    // Caption.
    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment = .center
    func text(_ string: String, y: CGFloat, font: NSFont, hex: UInt32, alpha: CGFloat) {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font, .foregroundColor: NSColor(cgColor: color(hex, alpha))!, .paragraphStyle: paragraph,
        ]
        NSGraphicsContext.saveGraphicsState()
        let flipped = NSGraphicsContext(cgContext: context, flipped: true)
        NSGraphicsContext.current = flipped
        (string as NSString).draw(in: CGRect(x: 0, y: y, width: size.width, height: 30), withAttributes: attributes)
        NSGraphicsContext.restoreGraphicsState()
    }
    let rounded = NSFont.systemFont(ofSize: 17, weight: .semibold).fontDescriptor.withDesign(.rounded)
        .flatMap { NSFont(descriptor: $0, size: 17) } ?? .systemFont(ofSize: 17, weight: .semibold)
    text("Drag Sylvra into Applications", y: 318, font: rounded, hex: 0xF1EAFF, alpha: 0.95)
    let serif = NSFont.systemFont(ofSize: 12).fontDescriptor.withDesign(.serif)
        .flatMap { NSFont(descriptor: $0.withSymbolicTraits(.italic), size: 12) } ?? .systemFont(ofSize: 12)
    text("A quiet place for focused review.", y: 346, font: serif, hex: 0xC9B8F2, alpha: 0.8)

    NSGraphicsContext.current = nil
    return rep
}

let arguments = CommandLine.arguments
guard arguments.count == 3, let icon = NSImage(contentsOfFile: arguments[1]) else {
    FileHandle.standardError.write("usage: make-background.swift <AppIcon.png> <out-dir>\n".data(using: .utf8)!)
    exit(1)
}
let out = URL(fileURLWithPath: arguments[2])
for (scale, name) in [(1.0, "background.png"), (2.0, "background@2x.png")] {
    let data = render(scale: scale, icon: icon).representation(using: .png, properties: [:])!
    try data.write(to: out.appending(path: name))
}
