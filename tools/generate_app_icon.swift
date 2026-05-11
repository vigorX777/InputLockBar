import AppKit
import Foundation

let arguments = CommandLine.arguments
guard arguments.count == 2 else {
    fputs("usage: swift generate_app_icon.swift <output-path>\n", stderr)
    exit(1)
}

let outputURL = URL(fileURLWithPath: arguments[1])
let canvasSize: CGFloat = 1024
let canvasRect = CGRect(x: 0, y: 0, width: canvasSize, height: canvasSize)

guard let bitmap = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: Int(canvasSize),
    pixelsHigh: Int(canvasSize),
    bitsPerSample: 8,
    samplesPerPixel: 4,
    hasAlpha: true,
    isPlanar: false,
    colorSpaceName: .deviceRGB,
    bytesPerRow: 0,
    bitsPerPixel: 0
) else {
    fputs("failed to create bitmap context\n", stderr)
    exit(1)
}

bitmap.size = NSSize(width: canvasSize, height: canvasSize)
NSGraphicsContext.saveGraphicsState()
guard let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
    fputs("failed to create graphics context\n", stderr)
    exit(1)
}
NSGraphicsContext.current = context

func color(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat, _ alpha: CGFloat = 1.0) -> NSColor {
    NSColor(calibratedRed: red / 255, green: green / 255, blue: blue / 255, alpha: alpha)
}

func fillRoundedRect(_ rect: CGRect, radius: CGFloat, color: NSColor) {
    color.setFill()
    NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
}

func drawLinearGradient(in rect: CGRect, from start: NSColor, to end: NSColor, angle: CGFloat) {
    let gradient = NSGradient(starting: start, ending: end)!
    gradient.draw(in: NSBezierPath(roundedRect: rect, xRadius: 0, yRadius: 0), angle: angle)
}

func drawShadowedRoundedRect(_ rect: CGRect, radius: CGFloat, fill: NSColor, shadowColor: NSColor, shadowOffset: CGSize, blur: CGFloat) {
    context.cgContext.saveGState()
    context.cgContext.setShadow(offset: shadowOffset, blur: blur, color: shadowColor.cgColor)
    fillRoundedRect(rect, radius: radius, color: fill)
    context.cgContext.restoreGState()
}

let backgroundRect = canvasRect.insetBy(dx: 72, dy: 72)
let backgroundPath = NSBezierPath(roundedRect: backgroundRect, xRadius: 230, yRadius: 230)

context.cgContext.saveGState()
backgroundPath.addClip()
let gradient = NSGradient(colorsAndLocations:
    (color(12, 20, 34), 0.0),
    (color(23, 41, 70), 0.42),
    (color(18, 93, 88), 1.0)
)!
gradient.draw(in: backgroundPath, angle: 310)
context.cgContext.restoreGState()

context.cgContext.saveGState()
context.cgContext.setShadow(offset: CGSize(width: 0, height: -8), blur: 24, color: color(255, 255, 255, 0.12).cgColor)
color(255, 255, 255, 0.10).setStroke()
backgroundPath.lineWidth = 3
backgroundPath.stroke()
context.cgContext.restoreGState()

let glowRect = CGRect(x: 170, y: 610, width: 520, height: 260)
let glow = NSGradient(colorsAndLocations:
    (color(104, 214, 198, 0.28), 0.0),
    (color(104, 214, 198, 0.0), 1.0)
)!
context.cgContext.saveGState()
NSBezierPath(ovalIn: glowRect).addClip()
glow.draw(in: NSBezierPath(ovalIn: glowRect), angle: 90)
context.cgContext.restoreGState()

let keyboardRect = CGRect(x: 186, y: 278, width: 652, height: 430)
let keyboardPath = NSBezierPath(roundedRect: keyboardRect, xRadius: 92, yRadius: 92)

context.cgContext.saveGState()
context.cgContext.setShadow(offset: CGSize(width: 0, height: -18), blur: 42, color: color(6, 10, 18, 0.38).cgColor)
let keyboardGradient = NSGradient(colorsAndLocations:
    (color(244, 237, 223), 0.0),
    (color(233, 225, 209), 1.0)
)!
keyboardGradient.draw(in: keyboardPath, angle: 90)
context.cgContext.restoreGState()

color(103, 97, 89, 0.18).setStroke()
keyboardPath.lineWidth = 2
keyboardPath.stroke()

let keyRects = [
    CGRect(x: 248, y: 488, width: 230, height: 150),
    CGRect(x: 546, y: 488, width: 230, height: 150),
    CGRect(x: 248, y: 330, width: 528, height: 106),
]

for (index, keyRect) in keyRects.enumerated() {
    let radius: CGFloat = index == 2 ? 40 : 46
    drawShadowedRoundedRect(
        keyRect,
        radius: radius,
        fill: index == 2 ? color(216, 231, 229) : color(255, 250, 241),
        shadowColor: color(24, 35, 52, 0.18),
        shadowOffset: CGSize(width: 0, height: -8),
        blur: 16
    )
    color(255, 255, 255, 0.55).setStroke()
    let strokePath = NSBezierPath(roundedRect: keyRect.insetBy(dx: 2, dy: 2), xRadius: radius - 2, yRadius: radius - 2)
    strokePath.lineWidth = 2
    strokePath.stroke()
}

let chineseAttributes: [NSAttributedString.Key: Any] = [
    .font: NSFont.systemFont(ofSize: 94, weight: .bold),
    .foregroundColor: color(24, 35, 52),
]
let latinAttributes: [NSAttributedString.Key: Any] = [
    .font: NSFont.monospacedSystemFont(ofSize: 92, weight: .bold),
    .foregroundColor: color(24, 35, 52),
]
let sublineAttributes: [NSAttributedString.Key: Any] = [
    .font: NSFont.monospacedSystemFont(ofSize: 44, weight: .semibold),
    .foregroundColor: color(32, 88, 85),
]

("文" as NSString).draw(
    in: CGRect(x: 310, y: 518, width: 110, height: 100),
    withAttributes: chineseAttributes
)
("A" as NSString).draw(
    in: CGRect(x: 622, y: 520, width: 78, height: 94),
    withAttributes: latinAttributes
)
("LOCKED INPUT" as NSString).draw(
    in: CGRect(x: 326, y: 357, width: 380, height: 48),
    withAttributes: sublineAttributes
)

let badgeRect = CGRect(x: 640, y: 176, width: 220, height: 220)
let badgePath = NSBezierPath(roundedRect: badgeRect, xRadius: 72, yRadius: 72)
context.cgContext.saveGState()
context.cgContext.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: color(0, 0, 0, 0.28).cgColor)
let badgeGradient = NSGradient(colorsAndLocations:
    (color(31, 197, 159), 0.0),
    (color(8, 146, 121), 1.0)
)!
badgeGradient.draw(in: badgePath, angle: 90)
context.cgContext.restoreGState()

color(255, 255, 255, 0.22).setStroke()
badgePath.lineWidth = 2
badgePath.stroke()

let shacklePath = NSBezierPath()
shacklePath.lineWidth = 26
shacklePath.lineCapStyle = .round
shacklePath.lineJoinStyle = .round
shacklePath.move(to: CGPoint(x: 717, y: 322))
shacklePath.curve(
    to: CGPoint(x: 783, y: 322),
    controlPoint1: CGPoint(x: 717, y: 370),
    controlPoint2: CGPoint(x: 783, y: 370)
)
color(248, 255, 252, 0.96).setStroke()
shacklePath.stroke()

let bodyRect = CGRect(x: 698, y: 220, width: 104, height: 112)
fillRoundedRect(bodyRect, radius: 24, color: color(248, 255, 252, 0.96))
fillRoundedRect(CGRect(x: 739, y: 248, width: 22, height: 38), radius: 10, color: color(8, 146, 121))
fillRoundedRect(CGRect(x: 730, y: 236, width: 40, height: 22), radius: 11, color: color(8, 146, 121))

let reflectionRect = CGRect(x: 148, y: 694, width: 330, height: 82)
let reflectionPath = NSBezierPath(roundedRect: reflectionRect, xRadius: 40, yRadius: 40)
context.cgContext.saveGState()
reflectionPath.addClip()
let reflection = NSGradient(colorsAndLocations:
    (color(255, 255, 255, 0.26), 0.0),
    (color(255, 255, 255, 0.0), 1.0)
)!
reflection.draw(in: reflectionPath, angle: 0)
context.cgContext.restoreGState()

NSGraphicsContext.restoreGraphicsState()

guard let pngData = bitmap.representation(using: .png, properties: [:]) else {
    fputs("failed to encode png\n", stderr)
    exit(1)
}

try FileManager.default.createDirectory(at: outputURL.deletingLastPathComponent(), withIntermediateDirectories: true)
try pngData.write(to: outputURL)
