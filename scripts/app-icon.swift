// Fits icon.png to Apple's app-icon template so macOS shows it as-is.
// macOS 26 puts icons whose outline doesn't match the standard rounded square on a grey plate.
//
//   swift scripts/app-icon.swift icon.png AppIcon-1024.png
import AppKit

let args = CommandLine.arguments
guard args.count == 3, let data = FileManager.default.contents(atPath: args[1]),
      let source = NSBitmapImageRep(data: data) else {
    fatalError("usage: app-icon.swift <source.png> <out.png>")
}

// The artwork's opaque area (its own rounded square), found from the alpha channel.
func opaqueBounds(of rep: NSBitmapImageRep) -> NSRect {
    var minX = rep.pixelsWide, maxX = -1, minY = rep.pixelsHigh, maxY = -1
    for y in 0..<rep.pixelsHigh {
        for x in 0..<rep.pixelsWide where (rep.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0.5 {
            minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
        }
    }
    precondition(maxX >= 0, "icon has no opaque pixels")
    // colorAt uses a top-left origin; drawing uses bottom-left.
    return NSRect(x: minX, y: rep.pixelsHigh - 1 - maxY, width: maxX - minX + 1, height: maxY - minY + 1)
}

/// Apple's continuous-corner rounded rectangle.
func appIconShape(_ r: NSRect, radius k: CGFloat) -> NSBezierPath {
    let path = NSBezierPath()
    // Points on one corner, as (along the edge, into the shape) multiples of the radius.
    func corner(_ point: (CGFloat, CGFloat) -> NSPoint) {
        path.curve(to: point(0.66993427, 0.06549600), controlPoint1: point(1.08849323, 0), controlPoint2: point(0.86840689, 0))
        path.line(to: point(0.63149399, 0.07491100))
        path.curve(to: point(0.07491100, 0.63149399), controlPoint1: point(0.37282392, 0.16905899), controlPoint2: point(0.16905899, 0.37282392))
        path.curve(to: point(0, 1.52866483), controlPoint1: point(0, 0.86840689), controlPoint2: point(0, 1.08849323))
    }
    path.move(to: NSPoint(x: r.minX + 1.52866483 * k, y: r.maxY))
    path.line(to: NSPoint(x: r.maxX - 1.52866483 * k, y: r.maxY))
    corner { a, b in NSPoint(x: r.maxX - a * k, y: r.maxY - b * k) } // top right
    path.line(to: NSPoint(x: r.maxX, y: r.minY + 1.52866483 * k))
    corner { a, b in NSPoint(x: r.maxX - b * k, y: r.minY + a * k) } // bottom right
    path.line(to: NSPoint(x: r.minX + 1.52866483 * k, y: r.minY))
    corner { a, b in NSPoint(x: r.minX + a * k, y: r.minY + b * k) } // bottom left
    path.line(to: NSPoint(x: r.minX, y: r.maxY - 1.52866483 * k))
    corner { a, b in NSPoint(x: r.minX + b * k, y: r.maxY - a * k) } // top left
    path.close()
    return path
}

let body = opaqueBounds(of: source)
let canvas: CGFloat = 1024
let shape = NSRect(x: 100, y: 100, width: 824, height: 824) // Apple's template: 824pt shape, 185.4pt corners
// Scale the artwork a little past the shape so its own rounder corners are trimmed off.
let artSize: CGFloat = 850
let scaleX = artSize / body.width, scaleY = artSize / body.height
let origin = NSPoint(x: canvas / 2 - artSize / 2, y: canvas / 2 - artSize / 2)
let drawRect = NSRect(
    x: origin.x - body.minX * scaleX, y: origin.y - body.minY * scaleY,
    width: CGFloat(source.pixelsWide) * scaleX, height: CGFloat(source.pixelsHigh) * scaleY)

// Background under the art: its own edge colour, in case a corner isn't fully covered.
let edgeColor = source.colorAt(x: Int(body.minX) + 24, y: source.pixelsHigh / 2) ?? .black

let output = NSBitmapImageRep(
    bitmapDataPlanes: nil, pixelsWide: Int(canvas), pixelsHigh: Int(canvas), bitsPerSample: 8,
    samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: output)
NSGraphicsContext.current?.imageInterpolation = .high
let mask = appIconShape(shape, radius: 185.4)
mask.addClip()
edgeColor.withAlphaComponent(1).setFill()
mask.fill()
source.draw(in: drawRect, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: false, hints: nil)
NSGraphicsContext.restoreGraphicsState()

try output.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: args[2]))
