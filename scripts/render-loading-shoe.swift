import AppKit
import Foundation
// Renders the loading screen's centered shoe, the same native Apple emoji as the app icon, at 52 pt @3x.
// Apple's emoji artwork is at most 160 px; at 3 px per point anything over ~53 pt is upscaled and fuzzy.
// Usage: swift scripts/render-loading-shoe.swift WikiTour/Assets.xcassets
let output = URL(fileURLWithPath: CommandLine.arguments[1]).appendingPathComponent("LoadingShoe.imageset")
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
let size = 156
let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
NSColor.clear.setFill()
NSRect(x: 0, y: 0, width: size, height: size).fill()
let text = NSAttributedString(string: "👟", attributes: [.font: NSFont(name: "Apple Color Emoji", size: 130)!])
let measured = text.size()
text.draw(at: NSPoint(x: (CGFloat(size) - measured.width) / 2, y: (CGFloat(size) - measured.height) / 2))
NSGraphicsContext.restoreGraphicsState()
try bitmap.representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent("LoadingShoe.png"))
let json: [String: Any] = ["images": [["idiom": "universal", "filename": "LoadingShoe.png", "scale": "3x"]], "info": ["author": "xcode", "version": 1]]
try JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys]).write(to: output.appendingPathComponent("Contents.json"))
