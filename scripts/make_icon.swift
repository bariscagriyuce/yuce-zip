// Draws the YUCE ZIP application icon (1024x1024 PNG).
// Usage: swift scripts/make_icon.swift <output.png>
import AppKit

let size: CGFloat = 1024
let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon_1024.png"

let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size),
                           bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                           colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
let ctx = NSGraphicsContext.current!.cgContext

func color(_ hex: UInt32, _ a: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: a)
}

// Background squircle (Big Sur grid: 824pt body, 100pt margin)
let bodyRect = NSRect(x: 100, y: 100, width: 824, height: 824)
let bodyPath = NSBezierPath(roundedRect: bodyRect, xRadius: 185, yRadius: 185)

ctx.saveGState()
let shadow = NSShadow()
shadow.shadowColor = NSColor.black.withAlphaComponent(0.35)
shadow.shadowBlurRadius = 28
shadow.shadowOffset = NSSize(width: 0, height: -12)
shadow.set()
color(0x1E3A8A).setFill()
bodyPath.fill()
ctx.restoreGState()

ctx.saveGState()
bodyPath.addClip()
NSGradient(colors: [color(0x312E81), color(0x1D4ED8), color(0x06B6D4)],
           atLocations: [0, 0.55, 1], colorSpace: .sRGB)!
    .draw(in: bodyRect, angle: 60)
// soft highlight
NSGradient(colors: [NSColor.white.withAlphaComponent(0.22), NSColor.white.withAlphaComponent(0)])!
    .draw(in: NSRect(x: 100, y: 560, width: 824, height: 364), angle: -90)
ctx.restoreGState()

// Document / archive card
let card = NSRect(x: 292, y: 210, width: 440, height: 590)
let fold: CGFloat = 120
let cardPath = NSBezierPath()
cardPath.move(to: NSPoint(x: card.minX + 36, y: card.minY))
cardPath.line(to: NSPoint(x: card.maxX - 36, y: card.minY))
cardPath.curve(to: NSPoint(x: card.maxX, y: card.minY + 36),
               controlPoint1: NSPoint(x: card.maxX - 16, y: card.minY),
               controlPoint2: NSPoint(x: card.maxX, y: card.minY + 16))
cardPath.line(to: NSPoint(x: card.maxX, y: card.maxY - fold))
cardPath.line(to: NSPoint(x: card.maxX - fold, y: card.maxY))
cardPath.line(to: NSPoint(x: card.minX + 36, y: card.maxY))
cardPath.curve(to: NSPoint(x: card.minX, y: card.maxY - 36),
               controlPoint1: NSPoint(x: card.minX + 16, y: card.maxY),
               controlPoint2: NSPoint(x: card.minX, y: card.maxY - 16))
cardPath.line(to: NSPoint(x: card.minX, y: card.minY + 36))
cardPath.curve(to: NSPoint(x: card.minX + 36, y: card.minY),
               controlPoint1: NSPoint(x: card.minX, y: card.minY + 16),
               controlPoint2: NSPoint(x: card.minX + 16, y: card.minY))
cardPath.close()

ctx.saveGState()
let cardShadow = NSShadow()
cardShadow.shadowColor = NSColor.black.withAlphaComponent(0.3)
cardShadow.shadowBlurRadius = 30
cardShadow.shadowOffset = NSSize(width: 0, height: -14)
cardShadow.set()
NSColor.white.setFill()
cardPath.fill()
ctx.restoreGState()

ctx.saveGState()
cardPath.addClip()
NSGradient(colors: [NSColor.white, color(0xE0F2FE)])!.draw(in: card, angle: -90)
ctx.restoreGState()

// Folded corner
let foldPath = NSBezierPath()
foldPath.move(to: NSPoint(x: card.maxX, y: card.maxY - fold))
foldPath.line(to: NSPoint(x: card.maxX - fold + 18, y: card.maxY - fold))
foldPath.curve(to: NSPoint(x: card.maxX - fold, y: card.maxY - fold + 18),
               controlPoint1: NSPoint(x: card.maxX - fold + 6, y: card.maxY - fold),
               controlPoint2: NSPoint(x: card.maxX - fold, y: card.maxY - fold + 6))
foldPath.line(to: NSPoint(x: card.maxX - fold, y: card.maxY))
foldPath.close()
color(0x93C5FD).setFill()
foldPath.fill()

// Zipper track
let zx = card.midX
let teethTop = card.maxY - 40
let teethBottom: CGFloat = 430
let toothH: CGFloat = 26
let toothW: CGFloat = 44
var y = teethTop
var left = true
let gold = NSGradient(colors: [color(0xFDE68A), color(0xF59E0B), color(0xB45309)])!
while y - toothH > teethBottom {
    let r = NSRect(x: left ? zx - toothW + 4 : zx - 4, y: y - toothH, width: toothW, height: toothH - 6)
    let p = NSBezierPath(roundedRect: r, xRadius: 6, yRadius: 6)
    ctx.saveGState(); p.addClip(); gold.draw(in: r, angle: -90); ctx.restoreGState()
    y -= toothH
    left.toggle()
}

// Zipper slider
let slider = NSRect(x: zx - 46, y: teethBottom - 70, width: 92, height: 92)
let sliderPath = NSBezierPath()
sliderPath.move(to: NSPoint(x: slider.minX, y: slider.maxY))
sliderPath.line(to: NSPoint(x: slider.maxX, y: slider.maxY))
sliderPath.line(to: NSPoint(x: slider.maxX - 14, y: slider.minY + 20))
sliderPath.curve(to: NSPoint(x: slider.minX + 14, y: slider.minY + 20),
                 controlPoint1: NSPoint(x: slider.maxX - 24, y: slider.minY - 4),
                 controlPoint2: NSPoint(x: slider.minX + 24, y: slider.minY - 4))
sliderPath.close()
ctx.saveGState(); sliderPath.addClip()
NSGradient(colors: [color(0xFCD34D), color(0xD97706)])!.draw(in: slider, angle: -90)
ctx.restoreGState()

// Pull tab
let tab = NSRect(x: zx - 30, y: 250, width: 60, height: 120)
let tabPath = NSBezierPath(roundedRect: tab, xRadius: 30, yRadius: 30)
ctx.saveGState(); tabPath.addClip()
NSGradient(colors: [color(0xFBBF24), color(0xB45309)])!.draw(in: tab, angle: -90)
ctx.restoreGState()
let hole = NSBezierPath(roundedRect: NSRect(x: zx - 13, y: 272, width: 26, height: 50), xRadius: 13, yRadius: 13)
color(0xE0F2FE).setFill()
hole.fill()

NSGraphicsContext.restoreGraphicsState()
let data = rep.representation(using: .png, properties: [:])!
try! data.write(to: URL(fileURLWithPath: out))
print("Wrote \(out)")
