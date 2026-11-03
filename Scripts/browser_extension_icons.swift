// Draws the Save to Cookbo browser extension's icons into BrowserExtension/:
// the app icon's art at each size, in a squircle like Apple's icons.
//
//   swift Scripts/browser_extension_icons.swift

import AppKit

let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let art = NSImage(contentsOf: root.appendingPathComponent("Cookbook/Assets.xcassets/AppIcon.appiconset/Cookbo.png"))!
    .cgImage(forProposedRect: nil, context: nil, hints: nil)!
let output = root.appendingPathComponent("BrowserExtension")

/// A superellipse, |x|ⁿ + |y|ⁿ = 1, which is close to the continuous corners of Apple's icons.
func squircle(in rect: CGRect, exponent n: CGFloat = 5) -> CGPath {
    let path = CGMutablePath()
    let steps = 720
    for step in 0..<steps {
        let t = CGFloat(step) / CGFloat(steps) * 2 * .pi
        let (c, s) = (cos(t), sin(t))
        let x = rect.midX + rect.width / 2 * copysign(pow(abs(c), 2 / n), c)
        let y = rect.midY + rect.height / 2 * copysign(pow(abs(s), 2 / n), s)
        step == 0 ? path.move(to: CGPoint(x: x, y: y)) : path.addLine(to: CGPoint(x: x, y: y))
    }
    path.closeSubpath()
    return path
}

func canvas(_ size: Int) -> CGContext {
    let context = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.interpolationQuality = .high
    return context
}

/// The art at `size`, halved a step at a time, which keeps small sizes smoother than one big jump.
func scaled(_ image: CGImage, to size: Int) -> CGImage {
    var image = image
    while image.width > size * 2 {
        let half = canvas(image.width / 2)
        half.draw(image, in: CGRect(x: 0, y: 0, width: half.width, height: half.height))
        image = half.makeImage()!
    }
    return image
}

func render(size: Int, to url: URL) throws {
    let context = canvas(size)
    let bounds = CGRect(x: 0, y: 0, width: size, height: size)
    context.addPath(squircle(in: bounds))
    context.clip()
    context.draw(scaled(art, to: size), in: bounds)

    let png = NSBitmapImageRep(cgImage: context.makeImage()!).representation(using: .png, properties: [:])!
    try png.write(to: url)
}

for size in [16, 32, 48, 96, 128] {
    try render(size: size, to: output.appendingPathComponent("icon-\(size).png"))
}
print("Wrote icon-{16,32,48,96,128}.png to \(output.path)")
