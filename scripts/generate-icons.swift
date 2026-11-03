#!/usr/bin/env swift
import AppKit
import ImageIO
import UniformTypeIdentifiers

// Original vector mark. Keep its normalized geometry in sync with CursorDesign.CursorMark.
let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
func drawIcon(size: Int, mac: Bool, destination: String) throws {
    let bitmap = mac ? CGImageAlphaInfo.premultipliedLast.rawValue : CGImageAlphaInfo.noneSkipLast.rawValue
    let context = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8,
        bytesPerRow: size * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: bitmap)!
    context.translateBy(x: 0, y: CGFloat(size)); context.scaleBy(x: CGFloat(size) / 1024, y: -CGFloat(size) / 1024)
    if mac { context.translateBy(x: 64, y: 64); context.scaleBy(x: 0.875, y: 0.875) }
    let rect = CGRect(x: 0, y: 0, width: 1024, height: 1024)
    let outline = mac ? CGPath(roundedRect: rect, cornerWidth: 256, cornerHeight: 256, transform: nil) : CGPath(rect: rect, transform: nil)
    context.addPath(outline); context.clip()
    let colors = [CGColor(red: 0.20, green: 0.77, blue: 0.81, alpha: 1),
                  CGColor(red: 0.08, green: 0.38, blue: 0.65, alpha: 1),
                  CGColor(red: 0.07, green: 0.18, blue: 0.38, alpha: 1)]
    let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: colors as CFArray, locations: [0,0.55,1])!
    context.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: 1024, y: 1024), options: [.drawsBeforeStartLocation,.drawsAfterEndLocation])
    context.setStrokeColor(CGColor(gray: 1, alpha: 0.19)); context.setLineWidth(12)
    context.strokeEllipse(in: CGRect(x: 225, y: 256, width: 717, height: 717))
    context.setStrokeColor(CGColor(gray: 1, alpha: 0.10)); context.setLineWidth(8)
    context.strokeEllipse(in: CGRect(x: 97, y: 128, width: 973, height: 973))
    let points: [(CGFloat, CGFloat)] = [(0.27,0.19),(0.78,0.57),(0.56,0.62),(0.46,0.84),(0.34,0.78),(0.44,0.57),(0.22,0.57)]
    let arrow = CGMutablePath()
    arrow.addLines(between: points.map { CGPoint(x: $0.0 * 1024, y: $0.1 * 1024) }); arrow.closeSubpath()
    context.setShadow(offset: CGSize(width: 0, height: 24), blur: 32, color: CGColor(gray: 0, alpha: 0.23))
    context.setFillColor(CGColor(gray: 1, alpha: 1)); context.addPath(arrow); context.fillPath()
    context.setShadow(offset: .zero, blur: 0, color: nil)
    if mac {
        context.setStrokeColor(CGColor(gray: 1, alpha: 0.25)); context.setLineWidth(2)
        context.addPath(CGPath(roundedRect: rect.insetBy(dx: 1, dy: 1), cornerWidth: 255, cornerHeight: 255, transform: nil)); context.strokePath()
    }
    let output = root.appendingPathComponent(destination)
    try FileManager.default.createDirectory(at: output.deletingLastPathComponent(), withIntermediateDirectories: true)
    let image = context.makeImage()!
    let writer = CGImageDestinationCreateWithURL(output as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(writer, image, nil)
    guard CGImageDestinationFinalize(writer) else { throw NSError(domain: "TheCursor.Icon", code: 1) }
}
for size in [16,32,128,256,512] {
    try drawIcon(size: size, mac: true, destination: "Resources/AppIcon.iconset/icon_\(size)x\(size).png")
    try drawIcon(size: size * 2, mac: true, destination: "Resources/AppIcon.iconset/icon_\(size)x\(size)@2x.png")
}
try drawIcon(size: 1024, mac: false, destination: "iOS/TheCursorConnect/Assets.xcassets/AppIcon.appiconset/AppIcon.png")
try drawIcon(size: 1024, mac: true, destination: "Resources/Brand/The-Cursor.png")
print("Generated matching macOS and iOS icons.")
