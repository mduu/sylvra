// Renders a README close-up: one or more regions of app screenshots on a soft violet background with rounded
// corners and a shadow.
//   swift scripts/readme/closeup.swift <out.png> <light|dark> <h|v> <screenshot.png:x,y,w,h> [more regions…]
// Regions are in units of a 1400 px wide preview of the 2940 px capture (factor 2.1).
import AppKit

let arguments = CommandLine.arguments
guard arguments.count >= 5 else {
    FileHandle.standardError.write("usage: closeup.swift out.png light|dark h|v file:x,y,w,h …\n".data(using: .utf8)!)
    exit(1)
}
let out = URL(fileURLWithPath: arguments[1])
let isDark = arguments[2] == "dark"
let horizontal = arguments[3] == "h"
let scale: CGFloat = 2.1

struct Region { let image: CGImage; let size: CGSize }
let regions: [Region] = arguments.dropFirst(4).map { spec in
    let parts = spec.split(separator: ":")
    let numbers = parts[1].split(separator: ",").compactMap { Double($0) }.map { CGFloat($0) * scale }
    let source = NSImage(contentsOfFile: String(parts[0]))!.cgImage(forProposedRect: nil, context: nil, hints: nil)!
    let rect = CGRect(x: numbers[0], y: numbers[1], width: numbers[2], height: numbers[3])
    return Region(image: source.cropping(to: rect)!, size: rect.size)
}

let padding: CGFloat = 56 * scale / 2
let gap: CGFloat = 28 * scale / 2
let radius: CGFloat = 12 * scale / 2
let contentWidth = horizontal
    ? regions.map(\.size.width).reduce(0, +) + gap * CGFloat(regions.count - 1)
    : regions.map(\.size.width).max()!
let contentHeight = horizontal
    ? regions.map(\.size.height).max()!
    : regions.map(\.size.height).reduce(0, +) + gap * CGFloat(regions.count - 1)
let size = CGSize(width: contentWidth + padding * 2, height: contentHeight + padding * 2)

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(
        srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
        blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}

let context = CGContext(
    data: nil, width: Int(size.width), height: Int(size.height), bitsPerComponent: 8, bytesPerRow: 0,
    space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
// Background: violet glow, darker for dark mode, lavender for light mode.
let stops = isDark ? [color(0x3D2378), color(0x1C0F3D), color(0x110826)] : [color(0xE9DEFF), color(0xD6C6F7), color(0xC4AEF0)]
let gradient = CGGradient(
    colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!, colors: stops as CFArray, locations: [0, 0.6, 1])!
context.drawRadialGradient(
    gradient, startCenter: CGPoint(x: size.width * 0.25, y: size.height), startRadius: 0,
    endCenter: CGPoint(x: size.width * 0.4, y: size.height * 0.5), endRadius: max(size.width, size.height),
    options: [.drawsAfterEndLocation])

// Regions, top-left origin.
var cursor = CGPoint(x: padding, y: padding)
for region in regions {
    let frame = CGRect(
        x: cursor.x, y: size.height - cursor.y - region.size.height, width: region.size.width,
        height: region.size.height)
    let path = CGPath(roundedRect: frame, cornerWidth: radius, cornerHeight: radius, transform: nil)
    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: -10), blur: 40, color: color(0x0B0420, isDark ? 0.6 : 0.35))
    context.addPath(path)
    context.setFillColor(color(isDark ? 0x150B2C : 0xFFFFFF))
    context.fillPath()
    context.restoreGState()
    context.saveGState()
    context.addPath(path)
    context.clip()
    context.draw(region.image, in: frame)
    context.restoreGState()
    context.addPath(path)
    context.setStrokeColor(isDark ? color(0xFFFFFF, 0.12) : color(0x2A1656, 0.12))
    context.setLineWidth(2)
    context.strokePath()
    if horizontal { cursor.x += region.size.width + gap } else { cursor.y += region.size.height + gap }
}

let rep = NSBitmapImageRep(cgImage: context.makeImage()!)
try! rep.representation(using: .png, properties: [:])!.write(to: out)
