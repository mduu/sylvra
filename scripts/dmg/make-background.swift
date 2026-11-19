// Renders the DMG window background (violet, large faint app icon, brushed arrow to Applications).
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

/// Deterministic noise, so every build renders the same strokes.
struct Random {
    var state: UInt64
    mutating func next() -> CGFloat {
        state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
        return CGFloat((state >> 33) % 10_000) / 10_000
    }
    mutating func signed() -> CGFloat { next() * 2 - 1 }
}

func cubic(_ p0: CGPoint, _ p1: CGPoint, _ p2: CGPoint, _ p3: CGPoint, _ t: CGFloat) -> CGPoint {
    let u = 1 - t
    let a = u * u * u, b = 3 * u * u * t, c = 3 * u * t * t, d = t * t * t
    return CGPoint(x: a * p0.x + b * p1.x + c * p2.x + d * p3.x, y: a * p0.y + b * p1.y + c * p2.y + d * p3.y)
}

/// A brush stroke: many thin bristles along the curve, tapered at both ends, with dry gaps.
func brush(
    _ context: CGContext, _ p0: CGPoint, _ p1: CGPoint, _ p2: CGPoint, _ p3: CGPoint, width: CGFloat,
    seed: UInt64, colors: [UInt32], taper: (CGFloat) -> CGFloat = { sin(.pi * $0) }
) {
    var random = Random(state: seed)
    let steps = 160
    let bristles = 44
    for bristle in 0..<bristles {
        let offset = (CGFloat(bristle) / CGFloat(bristles - 1) - 0.5)  // −0.5 … 0.5 across the stroke
        let wobble = random.signed() * 0.08
        let dryFrom = 0.55 + random.next() * 0.5  // outer bristles run dry earlier
        let alpha = 0.35 + random.next() * 0.5
        let hex = colors[bristle % colors.count]
        context.setStrokeColor(color(hex, alpha))
        context.setLineCap(.round)
        context.setLineWidth(1.0 + random.next() * 1.6)
        var previous: CGPoint?
        for step in 0...steps {
            let t = CGFloat(step) / CGFloat(steps)
            let taper = taper(t)
            if abs(offset) * 2 > dryFrom && t < 0.25 + abs(offset) * 0.3 { previous = nil; continue }
            let point = cubic(p0, p1, p2, p3, t)
            let ahead = cubic(p0, p1, p2, p3, min(t + 0.01, 1))
            let behind = cubic(p0, p1, p2, p3, max(t - 0.01, 0))
            let dx = ahead.x - behind.x, dy = ahead.y - behind.y
            let length = max(hypot(dx, dy), 0.0001)
            let normal = CGPoint(x: -dy / length, y: dx / length)
            let spread = width * taper * (offset + wobble * sin(t * 9 + CGFloat(bristle)))
            let current = CGPoint(x: point.x + normal.x * spread, y: point.y + normal.y * spread)
            if let previous, random.next() > 0.015 {
                context.move(to: previous)
                context.addLine(to: current)
                context.strokePath()
            }
            previous = current
        }
    }
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

    // Brushed golden arrow, swinging up and over from the app to Applications.
    let gold: [UInt32] = [0xF2D27A, 0xE9C46A, 0xFFE7A8, 0xD9B05A, 0xFFF1C9]
    let start = CGPoint(x: 240, y: 178)
    let control1 = CGPoint(x: 268, y: 78)
    let control2 = CGPoint(x: 376, y: 70)
    let tip = CGPoint(x: 418, y: 166)
    context.beginTransparencyLayer(auxiliaryInfo: nil)
    context.setShadow(offset: .zero, blur: 14, color: color(0xF2D27A, 0.35))
    context.beginTransparencyLayer(auxiliaryInfo: nil)
    // Lands with pressure: thin where the brush touches down, full width at the tip.
    brush(context, start, control1, control2, tip, width: 18, seed: 7, colors: gold) { t in
        min(t / 0.35, 1) * (0.35 + 0.65 * sin(.pi * min(t, 0.5)))
    }
    // Arrowhead: two strokes flicked back from the tip, ±38° around the arriving direction.
    let arriving = atan2(tip.y - control2.y, tip.x - control2.x)
    for (index, angle) in [arriving + .pi - 0.66, arriving + .pi + 0.66].enumerated() {
        let back = CGPoint(x: tip.x + cos(angle) * 34, y: tip.y + sin(angle) * 34)
        let bend = CGPoint(x: (tip.x * 2 + back.x) / 3, y: (tip.y * 2 + back.y) / 3)
        brush(context, tip, bend, bend, back, width: 13, seed: 11 + UInt64(index), colors: gold) { t in
            max(1 - t, 0) * 0.9 + 0.1
        }
    }
    context.endTransparencyLayer()
    context.endTransparencyLayer()

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
