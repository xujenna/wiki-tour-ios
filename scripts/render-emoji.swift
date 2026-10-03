import AppKit
import Foundation
let output = CommandLine.arguments[1]
let emojis = ["🪦", "🏰", "🕍", "⛪️", "🕌", "🛕", "🏫", "📚", "🎭", "💒", "🏛️", "🌉", "🌷", "🌲", "🗼", "🏠", "🛒", "⛲", "🗿", "🏨", "🍽️", "🛍️", "🏢", "🏺", "🏙️", "🏥"]
for emoji in emojis {
    let name = "Emoji-" + emoji.unicodeScalars.map { String($0.value, radix: 16) }.joined(separator: "-")
    let directory = URL(fileURLWithPath: output).appendingPathComponent(name + ".imageset")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let size = 144
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    NSColor.clear.setFill()
    NSRect(x: 0, y: 0, width: size, height: size).fill()
    let text = NSAttributedString(string: emoji, attributes: [.font: NSFont(name: "Apple Color Emoji", size: 120)!])
    let measured = text.size()
    text.draw(at: NSPoint(x: (144 - measured.width) / 2, y: (144 - measured.height) / 2))
    NSGraphicsContext.restoreGraphicsState()
    try bitmap.representation(using: .png, properties: [:])!.write(to: directory.appendingPathComponent(name + ".png"))
    let json: [String: Any] = ["images": [["idiom": "universal", "filename": name + ".png", "scale": "3x"]], "info": ["author": "xcode", "version": 1]]
    try JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys]).write(to: directory.appendingPathComponent("Contents.json"))
}
