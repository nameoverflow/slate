import AppKit
import CoreGraphics
import Foundation

public enum AnnotationTool: String, CaseIterable, Equatable {
    case none
    case rectangle
    case ellipse
    case arrow
    case brush
    case text
}

public enum StrokeThickness: Int, CaseIterable, Equatable {
    case thin = 0
    case medium = 1
    case thick = 2

    public var lineWidth: CGFloat {
        switch self {
        case .thin: return 2.5
        case .medium: return 4.5
        case .thick: return 7.5
        }
    }

    public var fontSize: CGFloat {
        switch self {
        case .thin: return 16
        case .medium: return 22
        case .thick: return 30
        }
    }

    public var dotDiameter: CGFloat {
        switch self {
        case .thin: return 5
        case .medium: return 8
        case .thick: return 11
        }
    }
}

public struct AnnotationColorPalette {
    public static let colors: [NSColor] = [
        NSColor(srgbRed: 1.0, green: 0.23, blue: 0.19, alpha: 1.0),   // Red
        NSColor(srgbRed: 1.0, green: 0.58, blue: 0.0, alpha: 1.0),    // Orange
        NSColor(srgbRed: 1.0, green: 0.80, blue: 0.0, alpha: 1.0),    // Yellow
        NSColor(srgbRed: 0.20, green: 0.78, blue: 0.35, alpha: 1.0),  // Green
        NSColor(srgbRed: 0.04, green: 0.52, blue: 1.0, alpha: 1.0),   // Blue
        NSColor(srgbRed: 1.0, green: 1.0, blue: 1.0, alpha: 1.0),     // White
        NSColor(srgbRed: 0.11, green: 0.11, blue: 0.12, alpha: 1.0)   // Near-Black
    ]
}

public struct AnnotationItem: Equatable {
    public enum Kind: Equatable {
        case rectangle(CGRect)
        case ellipse(CGRect)
        case arrow(start: CGPoint, end: CGPoint)
        case brush([CGPoint])
        case text(rect: CGRect, string: String, fontSize: CGFloat)
    }

    public let id: UUID
    public var kind: Kind
    public var color: NSColor
    public var lineWidth: CGFloat

    public init(id: UUID = UUID(), kind: Kind, color: NSColor, lineWidth: CGFloat) {
        self.id = id
        self.kind = kind
        self.color = color
        self.lineWidth = lineWidth
    }

    public static func == (lhs: AnnotationItem, rhs: AnnotationItem) -> Bool {
        lhs.id == rhs.id && lhs.kind == rhs.kind && lhs.lineWidth == rhs.lineWidth
    }
}

public enum AnnotationRenderer {
    /// Draws a single annotation in AppKit (bottom-left origin) coordinates.
    public static func draw(_ item: AnnotationItem, in ctx: CGContext) {
        ctx.saveGState()
        let cgColor = item.color.usingColorSpace(.sRGB)?.cgColor ?? item.color.cgColor
        ctx.setStrokeColor(cgColor)
        ctx.setFillColor(cgColor)
        ctx.setLineWidth(item.lineWidth)
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)

        switch item.kind {
        case .rectangle(let rect):
            let normalized = rect.standardized
            let path = CGPath(roundedRect: normalized, cornerWidth: 2, cornerHeight: 2, transform: nil)
            ctx.addPath(path)
            ctx.strokePath()

        case .ellipse(let rect):
            let normalized = rect.standardized
            ctx.strokeEllipse(in: normalized)

        case .arrow(let start, let end):
            drawArrow(from: start, to: end, lineWidth: item.lineWidth, in: ctx)

        case .brush(let points):
            guard !points.isEmpty else { break }
            if points.count == 1 {
                let r = item.lineWidth * 0.5
                ctx.fillEllipse(in: CGRect(x: points[0].x - r, y: points[0].y - r, width: r * 2, height: r * 2))
            } else {
                ctx.beginPath()
                ctx.move(to: points[0])
                for i in 1..<points.count {
                    let prev = points[i - 1]
                    let curr = points[i]
                    let mid = CGPoint(x: (prev.x + curr.x) * 0.5, y: (prev.y + curr.y) * 0.5)
                    ctx.addQuadCurve(to: mid, control: prev)
                }
                if let last = points.last {
                    ctx.addLine(to: last)
                }
                ctx.strokePath()
            }

        case .text(let rect, let string, let fontSize):
            guard !string.isEmpty else { break }
            let previousContext = NSGraphicsContext.current
            NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
            defer { NSGraphicsContext.current = previousContext }

            let paragraph = NSMutableParagraphStyle()
            paragraph.lineBreakMode = .byWordWrapping

            let shadow = NSShadow()
            shadow.shadowColor = NSColor.black.withAlphaComponent(0.35)
            shadow.shadowBlurRadius = 2
            shadow.shadowOffset = NSSize(width: 0, height: -1)

            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: fontSize, weight: .semibold),
                .foregroundColor: item.color,
                .paragraphStyle: paragraph,
                .shadow: shadow
            ]
            let attrStr = NSAttributedString(string: string, attributes: attributes)
            attrStr.draw(with: rect, options: [.usesLineFragmentOrigin, .usesFontLeading])
        }

        ctx.restoreGState()
    }

    private static func drawArrow(from start: CGPoint, to end: CGPoint, lineWidth: CGFloat, in ctx: CGContext) {
        let dx = end.x - start.x
        let dy = end.y - start.y
        let length = hypot(dx, dy)
        guard length >= 2 else { return }

        let angle = atan2(dy, dx)
        let headLength = min(max(lineWidth * 3.8, 12), length * 0.45)
        let headWidth = headLength * 0.72

        let shaftEnd = CGPoint(
            x: end.x - cos(angle) * (headLength * 0.75),
            y: end.y - sin(angle) * (headLength * 0.75)
        )

        ctx.beginPath()
        ctx.move(to: start)
        ctx.addLine(to: shaftEnd)
        ctx.strokePath()

        let leftWing = CGPoint(
            x: end.x - cos(angle) * headLength + sin(angle) * (headWidth * 0.5),
            y: end.y - sin(angle) * headLength - cos(angle) * (headWidth * 0.5)
        )
        let rightWing = CGPoint(
            x: end.x - cos(angle) * headLength - sin(angle) * (headWidth * 0.5),
            y: end.y - sin(angle) * headLength + cos(angle) * (headWidth * 0.5)
        )

        ctx.beginPath()
        ctx.move(to: end)
        ctx.addLine(to: leftWing)
        ctx.addLine(to: rightWing)
        ctx.closePath()
        ctx.fillPath()
    }

    /// Renders the cropped region of `baseImage` together with all annotations at full native pixel resolution.
    public static func renderFinalImage(
        baseImage: CGImage,
        viewBounds: CGRect,
        selectionRect: CGRect,
        annotations: [AnnotationItem]
    ) -> CGImage? {
        let clampedSelection = selectionRect.standardized.intersection(viewBounds)
        guard !clampedSelection.isNull, clampedSelection.width >= 1, clampedSelection.height >= 1,
              viewBounds.width > 0, viewBounds.height > 0 else {
            return nil
        }

        let scaleX = CGFloat(baseImage.width) / viewBounds.width
        let scaleY = CGFloat(baseImage.height) / viewBounds.height

        // CGImage cropping uses top-left pixel coordinates.
        let cropPixelRect = CGRect(
            x: clampedSelection.minX * scaleX,
            y: (viewBounds.height - clampedSelection.maxY) * scaleY,
            width: clampedSelection.width * scaleX,
            height: clampedSelection.height * scaleY
        ).integral

        guard let cropped = baseImage.cropping(to: cropPixelRect) else {
            return nil
        }

        let pixelWidth = cropped.width
        let pixelHeight = cropped.height
        guard pixelWidth > 0, pixelHeight > 0 else { return nil }

        let srgb = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        let colorSpace: CGColorSpace = {
            if let cs = baseImage.colorSpace, cs.supportsOutput {
                return cs
            }
            return srgb
        }()
        guard let ctx = CGContext(
            data: nil,
            width: pixelWidth,
            height: pixelHeight,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
        ) else {
            return cropped
        }

        ctx.interpolationQuality = .high
        ctx.draw(cropped, in: CGRect(x: 0, y: 0, width: pixelWidth, height: pixelHeight))

        // Align CGContext (bottom-left origin) to AppKit view coordinates of `clampedSelection`.
        ctx.saveGState()
        ctx.scaleBy(x: scaleX, y: scaleY)
        ctx.translateBy(x: -clampedSelection.minX, y: -clampedSelection.minY)
        for item in annotations {
            draw(item, in: ctx)
        }
        ctx.restoreGState()

        return ctx.makeImage()
    }

    public static func pngData(from cgImage: CGImage) -> Data? {
        let rep = NSBitmapImageRep(cgImage: cgImage)
        return rep.representation(using: .png, properties: [:])
    }

    public static func jpegData(from cgImage: CGImage, quality: CGFloat = 0.92) -> Data? {
        let rep = NSBitmapImageRep(cgImage: cgImage)
        return rep.representation(using: .jpeg, properties: [.compressionFactor: quality])
    }
}
