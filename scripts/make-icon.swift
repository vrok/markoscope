// Draws the app icon into an .iconset folder: swift make-icon.swift <out.iconset>
import AppKit

let output = URL(fileURLWithPath: CommandLine.arguments[1])
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

func render(pixels: Int) -> Data {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8,
        samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
        bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let s = CGFloat(pixels)

    // Paper card on the standard macOS icon grid (824/1024 body).
    let body = NSRect(x: s * 0.098, y: s * 0.098, width: s * 0.804, height: s * 0.804)
    let card = NSBezierPath(roundedRect: body, xRadius: s * 0.18, yRadius: s * 0.18)
    NSGradient(starting: NSColor(srgbRed: 0.99, green: 0.98, blue: 0.96, alpha: 1),
               ending: NSColor(srgbRed: 0.93, green: 0.90, blue: 0.84, alpha: 1))!.draw(in: card, angle: -90)

    // Text lines.
    NSColor(srgbRed: 0.80, green: 0.76, blue: 0.68, alpha: 1).setFill()
    for i in 0..<3 {
        let y = s * (0.26 + CGFloat(i) * 0.075)
        NSBezierPath(roundedRect: NSRect(x: s * 0.22, y: y, width: s * (i == 0 ? 0.36 : 0.56), height: s * 0.03),
                     xRadius: s * 0.015, yRadius: s * 0.015).fill()
    }

    // "M↓" mark.
    let font = NSFont(name: "Iowan Old Style Bold", size: s * 0.32) ?? .boldSystemFont(ofSize: s * 0.32)
    let mark = NSAttributedString(string: "M↓", attributes: [
        .font: font,
        .foregroundColor: NSColor(srgbRed: 0.17, green: 0.36, blue: 0.56, alpha: 1),
    ])
    let size = mark.size()
    mark.draw(at: NSPoint(x: (s - size.width) / 2, y: s * 0.47))

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

for points in [16, 32, 128, 256, 512] {
    try render(pixels: points).write(to: output.appendingPathComponent("icon_\(points)x\(points).png"))
    try render(pixels: points * 2).write(to: output.appendingPathComponent("icon_\(points)x\(points)@2x.png"))
}
