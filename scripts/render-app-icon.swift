import AppKit
let size = 1024
let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
NSColor.white.setFill()
NSRect(x: 0, y: 0, width: size, height: size).fill()
let background = NSImage(contentsOfFile: CommandLine.arguments.count > 2 ? CommandLine.arguments[2] : "resources/app-icon/sky-halftone.png")!
background.draw(in: NSRect(x: 0, y: 0, width: size, height: size))
let text = NSAttributedString(string: "👟", attributes: [.font: NSFont(name: "Apple Color Emoji", size: 640)!])
let measured = text.size()
text.draw(at: NSPoint(x: (1024 - measured.width) / 2, y: (1024 - measured.height) / 2))
NSGraphicsContext.restoreGraphicsState()
// An RGB context removes the alpha channel required to be absent in App Store icons.
let rgb = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: size * 4,
                    space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
rgb.draw(bitmap.cgImage!, in: CGRect(x: 0, y: 0, width: size, height: size))
let result = NSBitmapImageRep(cgImage: rgb.makeImage()!)
try result.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
