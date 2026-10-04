import AppKit
import Foundation
// Renders the loading screen's centered shoe, the same native Apple emoji as the app icon, at
// 240 pt @3x. Usage: swift scripts/render-loading-shoe.swift WikiTour/Assets.xcassets
let output = URL(fileURLWithPath: CommandLine.arguments[1]).appendingPathComponent("LoadingShoe.imageset")
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
let size = 720
let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
NSColor.clear.setFill()
NSRect(x: 0, y: 0, width: size, height: size).fill()
let text = NSAttributedString(string: "👟", attributes: [.font: NSFont(name: "Apple Color Emoji", size: 600)!])
let measured = text.size()
text.draw(at: NSPoint(x: (CGFloat(size) - measured.width) / 2, y: (CGFloat(size) - measured.height) / 2))
NSGraphicsContext.restoreGraphicsState()
try bitmap.representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent("LoadingShoe.png"))
let json: [String: Any] = ["images": [["idiom": "universal", "filename": "LoadingShoe.png", "scale": "3x"]], "info": ["author": "xcode", "version": 1]]
try JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys]).write(to: output.appendingPathComponent("Contents.json"))
