import AppKit
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

// Usage: swift icon.swift <out.png> <pixels> <ios|mac>
// Draws the Rote icon: a cream speech bubble on an indigo→violet gradient with
// three verse lines fading out and a coral heart on the last one ("by heart").
let args = CommandLine.arguments
let out = URL(fileURLWithPath: args[1]); let px = Int(args[2])!; let mac = args[3] == "mac"

let cs = CGColorSpace(name: CGColorSpace.sRGB)!
let ctx = CGContext(data: nil, width: px, height: px, bitsPerComponent: 8, bytesPerRow: 0, space: cs,
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
let s = CGFloat(px) / 1024
ctx.scaleBy(x: s, y: s)
func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor { CGColor(colorSpace: cs, components: [r/255, g/255, b/255, a])! }

// Mac icons supply their own shape: 824pt rounded square centred in 1024 with transparent margin.
let plate: CGRect = mac ? CGRect(x: 100, y: 100, width: 824, height: 824) : CGRect(x: 0, y: 0, width: 1024, height: 1024)
let plateRadius: CGFloat = mac ? 185 : 0
if mac {
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: rgb(0, 0, 0, 0.35))
    ctx.addPath(CGPath(roundedRect: plate, cornerWidth: plateRadius, cornerHeight: plateRadius, transform: nil))
    ctx.setFillColor(rgb(60, 50, 120)); ctx.fillPath()
    ctx.restoreGState()
}
ctx.saveGState()
ctx.addPath(CGPath(roundedRect: plate, cornerWidth: plateRadius, cornerHeight: plateRadius, transform: nil))
ctx.clip()
let bg = CGGradient(colorsSpace: cs, colors: [rgb(118, 124, 246), rgb(70, 48, 150)] as CFArray, locations: [0, 1])!
ctx.drawLinearGradient(bg, start: CGPoint(x: 512, y: 1024), end: CGPoint(x: 512, y: 0), options: [])
// Soft glow top-left for depth.
let glow = CGGradient(colorsSpace: cs, colors: [rgb(255, 255, 255, 0.22), rgb(255, 255, 255, 0)] as CFArray, locations: [0, 1])!
ctx.drawRadialGradient(glow, startCenter: CGPoint(x: 330, y: 760), startRadius: 0, endCenter: CGPoint(x: 330, y: 760), endRadius: 560, options: [])
ctx.restoreGState()

// Geometry scales with the plate so the mac version keeps the same proportions.
let k = plate.width / 1024
func P(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: plate.minX + x * k, y: plate.minY + y * k) }
func R(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> CGRect { CGRect(x: plate.minX + x * k, y: plate.minY + y * k, width: w * k, height: h * k) }

// Speech bubble with a tail at the bottom-left.
let bubble = CGMutablePath()
bubble.addRoundedRect(in: R(172, 318, 680, 470), cornerWidth: 120 * k, cornerHeight: 120 * k)
let tail = CGMutablePath()
tail.move(to: P(300, 330)); tail.addLine(to: P(262, 206))
tail.addQuadCurve(to: P(420, 322), control: P(300, 290)); tail.closeSubpath()
bubble.addPath(tail)
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -14 * k), blur: 36 * k, color: rgb(20, 10, 60, 0.45))
ctx.addPath(bubble); ctx.setFillColor(rgb(255, 247, 232)); ctx.fillPath()
ctx.restoreGState()

// Three verse lines fading out, then a heart.
let ink = (r: CGFloat(78), g: CGFloat(62), b: CGFloat(160))
let lines: [(x: CGFloat, y: CGFloat, w: CGFloat, a: CGFloat)] = [
    (262, 668, 500, 1.0), (262, 568, 380, 0.55), (262, 468, 440, 0.28)
]
for l in lines {
    ctx.setFillColor(rgb(ink.r, ink.g, ink.b, l.a))
    ctx.addPath(CGPath(roundedRect: R(l.x, l.y, l.w, 44), cornerWidth: 22 * k, cornerHeight: 22 * k, transform: nil)); ctx.fillPath()
}
// Short last line, faintest, with the heart finishing it.
ctx.setFillColor(rgb(ink.r, ink.g, ink.b, 0.14))
ctx.addPath(CGPath(roundedRect: R(262, 368, 250, 44), cornerWidth: 22 * k, cornerHeight: 22 * k, transform: nil)); ctx.fillPath()

func heart(center c: CGPoint, size d: CGFloat) -> CGPath {
    // Classic two-lobe heart from four cubic curves; `d` is the overall width.
    let p = CGMutablePath(); let w = d, h = d * 0.92
    let top = c.y + h * 0.25, bottom = c.y - h * 0.5
    p.move(to: CGPoint(x: c.x, y: bottom))
    p.addCurve(to: CGPoint(x: c.x - w * 0.5, y: c.y + h * 0.1), control1: CGPoint(x: c.x - w * 0.1, y: bottom + h * 0.15), control2: CGPoint(x: c.x - w * 0.5, y: c.y - h * 0.15))
    p.addCurve(to: CGPoint(x: c.x, y: c.y + h * 0.1), control1: CGPoint(x: c.x - w * 0.5, y: top + h * 0.12), control2: CGPoint(x: c.x - w * 0.05, y: top + h * 0.12))
    p.addCurve(to: CGPoint(x: c.x + w * 0.5, y: c.y + h * 0.1), control1: CGPoint(x: c.x + w * 0.05, y: top + h * 0.12), control2: CGPoint(x: c.x + w * 0.5, y: top + h * 0.12))
    p.addCurve(to: CGPoint(x: c.x, y: bottom), control1: CGPoint(x: c.x + w * 0.5, y: c.y - h * 0.15), control2: CGPoint(x: c.x + w * 0.1, y: bottom + h * 0.15))
    p.closeSubpath(); return p
}
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -6 * k), blur: 14 * k, color: rgb(255, 90, 110, 0.45))
ctx.addPath(heart(center: P(590, 392), size: 118 * k)); ctx.setFillColor(rgb(255, 104, 120)); ctx.fillPath()
ctx.restoreGState()
// Highlight on the heart for a little shine.
ctx.setFillColor(rgb(255, 255, 255, 0.55))
ctx.addEllipse(in: R(556, 404, 26, 18)); ctx.fillPath()

let image = ctx.makeImage()!
let dest = CGImageDestinationCreateWithURL(out as CFURL, UTType.png.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(dest, image, nil); CGImageDestinationFinalize(dest)
