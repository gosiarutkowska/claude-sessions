// Draws the app icon: terminal-dark rounded square with a green ">" prompt. Run: swift Resources/make-icon.swift
import AppKit

func png(_ size: CGFloat, _ url: URL) {
    let img = NSImage(size: NSSize(width: size, height: size))
    img.lockFocus()
    let s = size / 1024
    let rect = NSRect(x: 100 * s, y: 100 * s, width: 824 * s, height: 824 * s)   // macOS icon grid: 824 inside 1024
    NSColor(srgbRed: 0x34 / 255, green: 0x31 / 255, blue: 0x2C / 255, alpha: 1).setFill()
    NSBezierPath(roundedRect: rect, xRadius: 185 * s, yRadius: 185 * s).fill()
    let p = NSBezierPath()
    p.move(to: NSPoint(x: 360 * s, y: 690 * s))
    p.line(to: NSPoint(x: 600 * s, y: 512 * s))
    p.line(to: NSPoint(x: 360 * s, y: 334 * s))
    p.lineWidth = 78 * s
    p.lineCapStyle = .round
    p.lineJoinStyle = .round
    NSColor(srgbRed: 0x6C / 255, green: 0xCB / 255, blue: 0x5F / 255, alpha: 1).setStroke()
    p.stroke()
    aiMark(center: NSPoint(x: 800 * s, y: 224 * s), radius: 150 * s)
    img.unlockFocus()
    let rep = NSBitmapImageRep(data: img.tiffRepresentation!)!
    try! rep.representation(using: .png, properties: [:])!.write(to: url)
}

/// The "AI that gives" mark from aithatgives.org (same geometry as its mark.svg, viewBox -60…60), tucked into
/// the icon's corner on a light disc: a small "ai" in a circle, the dot over the i being the spark that
/// interfaces use for AI-made things. Two marks side by side, the newer one in front.
func aiMark(center c: NSPoint, radius: CGFloat) {
    let k = radius / 60
    func pt(_ x: CGFloat, _ y: CGFloat) -> NSPoint { NSPoint(x: c.x + k * x, y: c.y - k * y) }   // SVG y points down
    func circle(_ x: CGFloat, _ y: CGFloat, _ r: CGFloat) -> NSBezierPath {
        NSBezierPath(ovalIn: NSRect(x: c.x + k * (x - r), y: c.y - k * (y + r), width: 2 * k * r, height: 2 * k * r))
    }
    let paper = NSColor(srgbRed: 0xE8 / 255, green: 0xE7 / 255, blue: 0xE3 / 255, alpha: 1)
    let ink = NSColor(srgbRed: 0x1A / 255, green: 0x19 / 255, blue: 0x17 / 255, alpha: 1)
    paper.setFill(); circle(0, 0, 54).fill()
    ink.setStroke()
    let ring = circle(0, 0, 46); ring.lineWidth = 5 * k; ring.stroke()
    // inner group: translate(0,-2) scale(.82)
    func g(_ x: CGFloat, _ y: CGFloat) -> (CGFloat, CGFloat) { (x * 0.82, y * 0.82 - 2) }
    let (ax, ay) = g(-15, 12)
    let a = circle(ax, ay, 14 * 0.82); a.lineWidth = 7 * 0.82 * k; a.lineCapStyle = .round; a.stroke()
    for x: CGFloat in [-1, 17] {
        let l = NSBezierPath(); let (x1, y1) = g(x, -2); let (x2, y2) = g(x, 26)
        l.move(to: pt(x1, y1)); l.line(to: pt(x2, y2)); l.lineWidth = 7 * 0.82 * k; l.lineCapStyle = .round; l.stroke()
    }
    // the spark: translate(17,-22) scale(.85) inside the group, a four-point star of radius 13
    let (sx, sy) = g(17, -22); let m = 0.85 * 0.82
    func sp(_ x: CGFloat, _ y: CGFloat) -> NSPoint { pt(sx + x * m, sy + y * m) }
    let star = NSBezierPath()
    star.move(to: sp(0, -13))
    star.curve(to: sp(13, 0), controlPoint1: sp(1.2, -5), controlPoint2: sp(5, -1.2))
    star.curve(to: sp(0, 13), controlPoint1: sp(5, 1.2), controlPoint2: sp(1.2, 5))
    star.curve(to: sp(-13, 0), controlPoint1: sp(-1.2, 5), controlPoint2: sp(-5, 1.2))
    star.curve(to: sp(0, -13), controlPoint1: sp(-5, -1.2), controlPoint2: sp(-1.2, -5))
    star.close()
    ink.setFill(); star.fill()
}

let dir = URL(fileURLWithPath: "Resources/AppIcon.iconset")
try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    png(CGFloat(base), dir.appendingPathComponent("icon_\(base)x\(base).png"))
    png(CGFloat(base * 2), dir.appendingPathComponent("icon_\(base)x\(base)@2x.png"))
}
