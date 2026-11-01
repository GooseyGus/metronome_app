// Draws the app icon (light, dark and tinted) into the asset catalog.
// Run from the project folder: swift tools/make-icon.swift Metronome/Assets.xcassets/AppIcon.appiconset

import AppKit

func color(_ hex: UInt32) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
}

/// Draws `text` in DIN Alternate, the app's lettering, stretched to `size` and centred in `rect`.
func glyph(_ text: String, size: CGSize, in rect: CGRect, color c: NSColor) {
    let font = CTFontCreateWithName("DINAlternate-Bold" as CFString, 400, nil)
    var unichars = Array(text.utf16), glyphs = [CGGlyph](repeating: 0, count: unichars.count)
    CTFontGetGlyphsForCharacters(font, &unichars, &glyphs, unichars.count)
    let path = CTFontCreatePathForGlyph(font, glyphs[0], nil)!
    let bounds = path.boundingBoxOfPath
    var transform = CGAffineTransform(translationX: rect.midX - size.width / 2, y: rect.midY - size.height / 2)
        .scaledBy(x: size.width / bounds.width, y: size.height / bounds.height)
        .translatedBy(x: -bounds.minX, y: -bounds.minY)
    let ctx = NSGraphicsContext.current!.cgContext
    ctx.addPath(path.copy(using: &transform)!)
    ctx.setFillColor(c.cgColor)
    ctx.fillPath()
}

func render(_ name: String, background: UInt32, tileTop: UInt32, glyphTop: UInt32, tileBottom: UInt32, glyphBottom: UInt32, slash: UInt32) {
    let size = 1024
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    color(background).setFill()
    CGRect(x: 0, y: 0, width: size, height: size).fill()

    // Two number tiles with room between them for the slash (y is from the bottom here).
    let tileWidth: CGFloat = 345
    let top = CGRect(x: 60, y: 168, width: tileWidth, height: 688)
    let bottom = CGRect(x: CGFloat(size) - 60 - tileWidth, y: 168, width: tileWidth, height: 688)
    color(tileTop).setFill()
    NSBezierPath(roundedRect: top, xRadius: 90, yRadius: 90).fill()
    color(tileBottom).setFill()
    NSBezierPath(roundedRect: bottom, xRadius: 90, yRadius: 90).fill()
    let digit = CGSize(width: 250, height: 534)
    glyph("4", size: digit, in: top, color: color(glyphTop))
    glyph("4", size: digit, in: bottom, color: color(glyphBottom))

    // The slash: as thick as the 4s' strokes and a little taller than them, as in a printed time signature.
    let stroke: CGFloat = 58, height: CGFloat = 580, run: CGFloat = 120
    let mid = CGPoint(x: CGFloat(size) / 2, y: top.midY)
    let path = NSBezierPath()
    path.move(to: CGPoint(x: mid.x - run / 2 - stroke / 2, y: mid.y - height / 2))
    path.line(to: CGPoint(x: mid.x - run / 2 + stroke / 2, y: mid.y - height / 2))
    path.line(to: CGPoint(x: mid.x + run / 2 + stroke / 2, y: mid.y + height / 2))
    path.line(to: CGPoint(x: mid.x + run / 2 - stroke / 2, y: mid.y + height / 2))
    path.close()
    color(slash).setFill()
    path.fill()

    NSGraphicsContext.restoreGraphicsState()
    // Icons must be opaque.
    let cg = rep.cgImage!
    let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
    ctx.draw(cg, in: CGRect(x: 0, y: 0, width: size, height: size))
    let out = NSBitmapImageRep(cgImage: ctx.makeImage()!)
    try! out.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1] + "/" + name))
}

render("AppIcon.png", background: 0x0A2947, tileTop: 0x8B5E3C, glyphTop: 0xF3E4C9, tileBottom: 0xD3D4C0, glyphBottom: 0x0A2947, slash: 0xF3E4C9)
render("AppIcon-Dark.png", background: 0x061A2E, tileTop: 0x8B5E3C, glyphTop: 0xF3E4C9, tileBottom: 0xD3D4C0, glyphBottom: 0x061A2E, slash: 0xF3E4C9)
render("AppIcon-Tinted.png", background: 0x000000, tileTop: 0x5C5C5C, glyphTop: 0xFFFFFF, tileBottom: 0xD0D0D0, glyphBottom: 0x000000, slash: 0xFFFFFF)
