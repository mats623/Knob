// Renders Resources/AppIcon.icns. Run: swift Tools/make-icon.swift
import AppKit

func render(_ px: Int) -> Data {
    let s = CGFloat(px)
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

    // Base tile
    let inset = s * 0.1
    let tile = NSRect(x: inset, y: inset, width: s - 2 * inset, height: s - 2 * inset)
    let tilePath = NSBezierPath(roundedRect: tile, xRadius: tile.width * 0.225, yRadius: tile.width * 0.225)
    NSGradient(starting: NSColor(white: 0.98, alpha: 1), ending: NSColor(white: 0.86, alpha: 1))!.draw(in: tilePath, angle: -90)

    let center = NSPoint(x: s / 2, y: s / 2)

    // Tick marks around the knob
    NSColor(white: 0.55, alpha: 1).setStroke()
    for i in 0...10 {
        let angle = (225 - Double(i) * 27) * .pi / 180
        let r1 = s * 0.30, r2 = s * 0.33
        let tick = NSBezierPath()
        tick.move(to: NSPoint(x: center.x + r1 * cos(angle), y: center.y + r1 * sin(angle)))
        tick.line(to: NSPoint(x: center.x + r2 * cos(angle), y: center.y + r2 * sin(angle)))
        tick.lineWidth = s * 0.012
        tick.lineCapStyle = .round
        tick.stroke()
    }

    // Knob
    let radius = s * 0.24
    let knob = NSBezierPath(ovalIn: NSRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
    let shadow = NSShadow()
    shadow.shadowColor = NSColor(white: 0, alpha: 0.35)
    shadow.shadowBlurRadius = s * 0.03
    shadow.shadowOffset = NSSize(width: 0, height: -s * 0.012)
    NSGraphicsContext.saveGraphicsState()
    shadow.set()
    NSGradient(starting: NSColor(white: 0.24, alpha: 1), ending: NSColor(white: 0.1, alpha: 1))!.draw(in: knob, angle: -90)
    NSGraphicsContext.restoreGraphicsState()

    // Indicator
    let angle = 60.0 * .pi / 180
    let dotR = s * 0.022
    let dotCenter = NSPoint(x: center.x + radius * 0.68 * cos(angle), y: center.y + radius * 0.68 * sin(angle))
    NSColor.white.setFill()
    NSBezierPath(ovalIn: NSRect(x: dotCenter.x - dotR, y: dotCenter.y - dotR, width: dotR * 2, height: dotR * 2)).fill()

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let root = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : ".")
let iconset = FileManager.default.temporaryDirectory.appendingPathComponent("AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try! FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for size in [16, 32, 128, 256, 512] {
    try! render(size).write(to: iconset.appendingPathComponent("icon_\(size)x\(size).png"))
    try! render(size * 2).write(to: iconset.appendingPathComponent("icon_\(size)x\(size)@2x.png"))
}
let task = Process()
task.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
task.arguments = ["-c", "icns", iconset.path, "-o", root.appendingPathComponent("Resources/AppIcon.icns").path]
try! task.run()
task.waitUntilExit()
