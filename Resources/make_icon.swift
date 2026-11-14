import AppKit

let outDir = CommandLine.arguments[1]
let sizes: [(Int, String)] = [
    (16, "icon_16x16.png"),
    (32, "icon_16x16@2x.png"),
    (32, "icon_32x32.png"),
    (64, "icon_32x32@2x.png"),
    (128, "icon_128x128.png"),
    (256, "icon_128x128@2x.png"),
    (256, "icon_256x256.png"),
    (512, "icon_256x256@2x.png"),
    (512, "icon_512x512.png"),
    (1024, "icon_512x512@2x.png")
]

func renderIcon(px: Int) -> Data? {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: px,
        pixelsHigh: px,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    )!
    rep.size = NSSize(width: px, height: px)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

    let s = CGFloat(px)
    let inset = s * 0.08
    let rect = CGRect(x: inset, y: inset, width: s - inset * 2, height: s - inset * 2)
    let path = NSBezierPath(roundedRect: rect, xRadius: rect.width * 0.225, yRadius: rect.height * 0.225)

    let grad = NSGradient(colors: [
        NSColor(srgbRed: 0.21, green: 0.24, blue: 0.29, alpha: 1.0),
        NSColor(srgbRed: 0.09, green: 0.11, blue: 0.14, alpha: 1.0)
    ])!
    grad.draw(in: path, angle: -90)

    NSColor.white.withAlphaComponent(0.22).setStroke()
    path.lineWidth = max(1, s * 0.015)
    path.stroke()

    if let symbol = NSImage(systemSymbolName: "viewfinder", accessibilityDescription: nil) {
        let cfg = NSImage.SymbolConfiguration(pointSize: s * 0.48, weight: .medium)
        let tinted = symbol.withSymbolConfiguration(cfg)!
        tinted.lockFocus()
        NSColor.white.set()
        NSRect(origin: .zero, size: tinted.size).fill(using: .sourceAtop)
        tinted.unlockFocus()
        let symSize = tinted.size
        let dest = CGRect(
            x: (s - symSize.width) * 0.5,
            y: (s - symSize.height) * 0.5,
            width: symSize.width,
            height: symSize.height
        )
        tinted.draw(in: dest)
    }

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])
}

for (px, name) in sizes {
    if let data = renderIcon(px: px) {
        let url = URL(fileURLWithPath: outDir).appendingPathComponent(name)
        try? data.write(to: url)
    }
}
