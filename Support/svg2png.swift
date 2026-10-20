// Renders an SVG to a square PNG (black on transparent) for use as a template image.
// Usage: swift svg2png.swift in.svg out.png size
import AppKit
let args = CommandLine.arguments
guard args.count == 4, let img = NSImage(contentsOf: URL(fileURLWithPath: args[1])), let px = Int(args[3]) else {
    FileHandle.standardError.write("cannot load \(args.dropFirst().first ?? "")\n".data(using: .utf8)!); exit(1)
}
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8, samplesPerPixel: 4,
                           hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
img.draw(in: NSRect(x: 0, y: 0, width: px, height: px))
NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: args[2]))
