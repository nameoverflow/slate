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

    public static func colorsMatch(_ lhs: NSColor, _ rhs: NSColor) -> Bool {
        guard let a = lhs.usingColorSpace(.sRGB), let b = rhs.usingColorSpace(.sRGB) else {
            return lhs == rhs
        }
        return abs(a.redComponent - b.redComponent) < 0.01
            && abs(a.greenComponent - b.greenComponent) < 0.01
            && abs(a.blueComponent - b.blueComponent) < 0.01
            && abs(a.alphaComponent - b.alphaComponent) < 0.01
    }

    public static func nearestThickness(for item: AnnotationItem) -> StrokeThickness {
        switch item.kind {
        case .text(_, _, let fontSize):
            return StrokeThickness.allCases.min(by: { abs($0.fontSize - fontSize) < abs($1.fontSize - fontSize) }) ?? .medium
        default:
            return StrokeThickness.allCases.min(by: { abs($0.lineWidth - item.lineWidth) < abs($1.lineWidth - item.lineWidth) }) ?? .medium
        }
    }
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
        lhs.id == rhs.id
            && lhs.kind == rhs.kind
            && lhs.lineWidth == rhs.lineWidth
            && AnnotationColorPalette.colorsMatch(lhs.color, rhs.color)
    }
}

public enum AnnotationHandle: Equatable {
    case corner(SelectionHandle)
    case arrowStart
    case arrowEnd
}

public enum AnnotationGeometry {
    public static func textAttributes(color: NSColor, fontSize: CGFloat) -> [NSAttributedString.Key: Any] {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byWordWrapping

        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.35)
        shadow.shadowBlurRadius = 2
        shadow.shadowOffset = NSSize(width: 0, height: -1)

        return [
            .font: NSFont.systemFont(ofSize: fontSize, weight: .semibold),
            .foregroundColor: color,
            .paragraphStyle: paragraph,
            .shadow: shadow
        ]
    }

    public static func textBoxSize(for string: String, fontSize: CGFloat, width: CGFloat) -> CGSize {
        let clampedW = max(40, ceil(width))
        let attrs = textAttributes(color: .white, fontSize: fontSize)
        let sample = string.isEmpty ? " " : string
        let bounds = (sample as NSString).boundingRect(
            with: CGSize(width: clampedW, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: attrs
        )
        return CGSize(width: clampedW, height: max(fontSize + 8, ceil(bounds.height) + 4))
    }

    public static func boundingBox(for item: AnnotationItem) -> CGRect {
        switch item.kind {
        case .rectangle(let rect), .ellipse(let rect):
            return rect.standardized
        case .arrow(let start, let end):
            return SelectionGeometry.normalizedRect(from: start, to: end)
        case .brush(let points):
            guard let first = points.first else { return .zero }
            var minX = first.x
            var maxX = first.x
            var minY = first.y
            var maxY = first.y
            for pt in points.dropFirst() {
                minX = min(minX, pt.x)
                maxX = max(maxX, pt.x)
                minY = min(minY, pt.y)
                maxY = max(maxY, pt.y)
            }
            return CGRect(x: minX, y: minY, width: max(1, maxX - minX), height: max(1, maxY - minY))
        case .text(let rect, _, _):
            return rect.standardized
        }
    }

    public static func handles(for item: AnnotationItem) -> [(AnnotationHandle, CGPoint)] {
        switch item.kind {
        case .rectangle(let rect), .ellipse(let rect):
            let r = rect.standardized
            return SelectionHandle.allCases.map { (.corner($0), SelectionGeometry.handleCenter($0, in: r)) }
        case .arrow(let start, let end):
            return [(.arrowStart, start), (.arrowEnd, end)]
        case .brush:
            let r = boundingBox(for: item)
            let corners: [SelectionHandle] = [.topLeft, .topRight, .bottomRight, .bottomLeft]
            return corners.map { (.corner($0), SelectionGeometry.handleCenter($0, in: r)) }
        case .text(let rect, _, _):
            let r = rect.standardized
            return [
                (.corner(.left), SelectionGeometry.handleCenter(.left, in: r)),
                (.corner(.right), SelectionGeometry.handleCenter(.right, in: r))
            ]
        }
    }

    public static func hitTestHandle(
        at point: CGPoint,
        for item: AnnotationItem,
        radius: CGFloat = 8
    ) -> AnnotationHandle? {
        for (handle, center) in handles(for: item) {
            if hypot(point.x - center.x, point.y - center.y) <= radius {
                return handle
            }
        }
        return nil
    }

    public static func hitTest(_ item: AnnotationItem, at point: CGPoint) -> Bool {
        let tolerance = max(8.0, item.lineWidth * 0.5 + 6.0)
        switch item.kind {
        case .rectangle(let rect):
            let r = rect.standardized
            guard r.insetBy(dx: -tolerance, dy: -tolerance).contains(point) else { return false }
            if r.width > tolerance * 2 && r.height > tolerance * 2 {
                return !r.insetBy(dx: tolerance, dy: tolerance).contains(point)
            }
            return true

        case .ellipse(let rect):
            let r = rect.standardized
            guard r.insetBy(dx: -tolerance, dy: -tolerance).contains(point) else { return false }
            if r.width <= tolerance * 2 || r.height <= tolerance * 2 {
                return true
            }
            return distanceToEllipsePerimeter(r, from: point) <= tolerance

        case .arrow(let start, let end):
            let dx = end.x - start.x
            let dy = end.y - start.y
            let length = hypot(dx, dy)
            let headLength = min(max(item.lineWidth * 3.8, 12), length * 0.45)
            let nearHead = hypot(point.x - end.x, point.y - end.y) <= max(tolerance, headLength * 0.6)
            return nearHead || distanceFromPoint(point, toSegmentStart: start, end: end) <= tolerance

        case .brush(let points):
            guard !points.isEmpty else { return false }
            if points.count == 1 {
                return hypot(point.x - points[0].x, point.y - points[0].y) <= tolerance
            }
            for i in 1..<points.count {
                if distanceFromPoint(point, toSegmentStart: points[i - 1], end: points[i]) <= tolerance {
                    return true
                }
            }
            return false

        case .text(let rect, _, _):
            return rect.standardized.insetBy(dx: -4, dy: -4).contains(point)
        }
    }

    public static func moving(_ item: AnnotationItem, by delta: CGPoint, within bounds: CGRect) -> AnnotationItem {
        let bbox = boundingBox(for: item)
        let minDx = bounds.minX - bbox.minX
        let maxDx = bounds.maxX - bbox.maxX
        let minDy = bounds.minY - bbox.minY
        let maxDy = bounds.maxY - bbox.maxY

        let dx = (minDx <= maxDx) ? max(minDx, min(delta.x, maxDx)) : delta.x
        let dy = (minDy <= maxDy) ? max(minDy, min(delta.y, maxDy)) : delta.y

        var updated = item
        switch item.kind {
        case .rectangle(let rect):
            updated.kind = .rectangle(rect.standardized.offsetBy(dx: dx, dy: dy))
        case .ellipse(let rect):
            updated.kind = .ellipse(rect.standardized.offsetBy(dx: dx, dy: dy))
        case .arrow(let start, let end):
            updated.kind = .arrow(
                start: CGPoint(x: start.x + dx, y: start.y + dy),
                end: CGPoint(x: end.x + dx, y: end.y + dy)
            )
        case .brush(let points):
            updated.kind = .brush(points.map { CGPoint(x: $0.x + dx, y: $0.y + dy) })
        case .text(let rect, let string, let fontSize):
            updated.kind = .text(rect: rect.standardized.offsetBy(dx: dx, dy: dy), string: string, fontSize: fontSize)
        }
        return updated
    }

    public static func resizing(
        _ initialItem: AnnotationItem,
        handle: AnnotationHandle,
        to point: CGPoint,
        within bounds: CGRect,
        snapAngle: Bool = false
    ) -> AnnotationItem {
        let clamped = SelectionGeometry.clampPoint(point, to: bounds)
        var updated = initialItem

        switch (initialItem.kind, handle) {
        case (.rectangle(let rect), .corner(let corner)):
            let resized = SelectionGeometry.resizedRect(from: rect.standardized, handle: corner, to: clamped, bounds: bounds, minSize: 6)
            updated.kind = .rectangle(resized)

        case (.ellipse(let rect), .corner(let corner)):
            let resized = SelectionGeometry.resizedRect(from: rect.standardized, handle: corner, to: clamped, bounds: bounds, minSize: 6)
            updated.kind = .ellipse(resized)

        case (.arrow(_, let end), .arrowStart):
            let candidate = snapAngle ? angleSnappedPoint(from: end, to: clamped, bounds: bounds) : clamped
            if hypot(end.x - candidate.x, end.y - candidate.y) >= 4 {
                updated.kind = .arrow(start: candidate, end: end)
            }

        case (.arrow(let start, _), .arrowEnd):
            let candidate = snapAngle ? angleSnappedPoint(from: start, to: clamped, bounds: bounds) : clamped
            if hypot(candidate.x - start.x, candidate.y - start.y) >= 4 {
                updated.kind = .arrow(start: start, end: candidate)
            }

        case (.brush(let points), .corner(let corner)):
            let oldRect = boundingBox(for: initialItem)
            let newRect = SelectionGeometry.resizedRect(from: oldRect, handle: corner, to: clamped, bounds: bounds, minSize: 8)
            let scaleX = oldRect.width > 0.5 ? newRect.width / oldRect.width : 1
            let scaleY = oldRect.height > 0.5 ? newRect.height / oldRect.height : 1
            let scaled = points.map { pt in
                CGPoint(
                    x: newRect.minX + (pt.x - oldRect.minX) * scaleX,
                    y: newRect.minY + (pt.y - oldRect.minY) * scaleY
                )
            }
            updated.kind = .brush(scaled)

        case (.text(let rect, let string, let fontSize), .corner(let corner)):
            let oldRect = rect.standardized
            let minW: CGFloat = 40
            var minX = oldRect.minX
            var maxX = oldRect.maxX
            switch corner {
            case .left, .topLeft, .bottomLeft:
                minX = min(clamped.x, maxX - minW)
            case .right, .topRight, .bottomRight:
                maxX = max(clamped.x, minX + minW)
            default:
                break
            }
            let newWidth = maxX - minX
            let newSize = textBoxSize(for: string, fontSize: fontSize, width: newWidth)
            let newY = max(bounds.minY, min(oldRect.maxY - newSize.height, bounds.maxY - newSize.height))
            updated.kind = .text(
                rect: CGRect(x: minX, y: newY, width: newWidth, height: min(newSize.height, bounds.height)),
                string: string,
                fontSize: fontSize
            )

        default:
            break
        }

        return updated
    }

    public static func updatingStyle(
        _ item: AnnotationItem,
        color: NSColor? = nil,
        thickness: StrokeThickness? = nil,
        within bounds: CGRect
    ) -> AnnotationItem {
        var updated = item
        if let color = color {
            updated.color = color
        }
        if let thickness = thickness {
            updated.lineWidth = thickness.lineWidth
            if case .text(let rect, let string, _) = item.kind {
                let newFontSize = thickness.fontSize
                let newSize = textBoxSize(for: string, fontSize: newFontSize, width: rect.width)
                let newX = max(bounds.minX, min(rect.minX, bounds.maxX - rect.width))
                let newY = max(bounds.minY, min(rect.maxY - newSize.height, bounds.maxY - newSize.height))
                updated.kind = .text(
                    rect: CGRect(x: newX, y: newY, width: rect.width, height: min(newSize.height, bounds.height)),
                    string: string,
                    fontSize: newFontSize
                )
            }
        }
        return updated
    }

    public static func angleSnappedPoint(from start: CGPoint, to end: CGPoint, bounds: CGRect) -> CGPoint {
        let dx = end.x - start.x
        let dy = end.y - start.y
        let len = hypot(dx, dy)
        let angle = atan2(dy, dx)
        let snapped = round(angle / (.pi / 4)) * (.pi / 4)
        let candidate = CGPoint(x: start.x + cos(snapped) * len, y: start.y + sin(snapped) * len)
        return SelectionGeometry.clampPoint(candidate, to: bounds)
    }

    private static func distanceFromPoint(_ p: CGPoint, toSegmentStart a: CGPoint, end b: CGPoint) -> CGFloat {
        let abx = b.x - a.x
        let aby = b.y - a.y
        let lenSq = abx * abx + aby * aby
        guard lenSq > 1e-6 else {
            return hypot(p.x - a.x, p.y - a.y)
        }
        let t = max(0, min(1, ((p.x - a.x) * abx + (p.y - a.y) * aby) / lenSq))
        let projX = a.x + t * abx
        let projY = a.y + t * aby
        return hypot(p.x - projX, p.y - projY)
    }

    private static func distanceToEllipsePerimeter(_ rect: CGRect, from point: CGPoint) -> CGFloat {
        let cx = rect.midX
        let cy = rect.midY
        let rx = rect.width * 0.5
        let ry = rect.height * 0.5
        let segments = 48
        var minDist = CGFloat.greatestFiniteMagnitude
        var prev = CGPoint(x: cx + rx, y: cy)
        for i in 1...segments {
            let theta = (CGFloat(i) / CGFloat(segments)) * (.pi * 2)
            let curr = CGPoint(x: cx + cos(theta) * rx, y: cy + sin(theta) * ry)
            minDist = min(minDist, distanceFromPoint(point, toSegmentStart: prev, end: curr))
            prev = curr
        }
        return minDist
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

            let attributes = AnnotationGeometry.textAttributes(color: item.color, fontSize: fontSize)
            let attrStr = NSAttributedString(string: string, attributes: attributes)
            attrStr.draw(with: rect, options: [.usesLineFragmentOrigin, .usesFontLeading])
        }

        ctx.restoreGState()
    }

    public static func drawSelectionChrome(for item: AnnotationItem, in ctx: CGContext) {
        ctx.saveGState()

        switch item.kind {
        case .ellipse, .brush:
            let bbox = AnnotationGeometry.boundingBox(for: item)
            ctx.setStrokeColor(NSColor.white.withAlphaComponent(0.85).cgColor)
            ctx.setLineWidth(1.0)
            ctx.setLineDash(phase: 0, lengths: [4, 3])
            ctx.stroke(bbox)
            ctx.setLineDash(phase: 0, lengths: [])

        case .text(let rect, _, _):
            let guide = rect.standardized.insetBy(dx: -3, dy: -2)
            ctx.setStrokeColor(NSColor.white.withAlphaComponent(0.85).cgColor)
            ctx.setLineWidth(1.0)
            ctx.setLineDash(phase: 0, lengths: [4, 3])
            ctx.stroke(guide)
            ctx.setLineDash(phase: 0, lengths: [])

        case .rectangle, .arrow:
            break
        }

        let knobSize: CGFloat = 7.5
        for (_, center) in AnnotationGeometry.handles(for: item) {
            let knobRect = CGRect(
                x: center.x - knobSize * 0.5,
                y: center.y - knobSize * 0.5,
                width: knobSize,
                height: knobSize
            )
            ctx.setFillColor(NSColor.white.cgColor)
            ctx.fillEllipse(in: knobRect)
            ctx.setStrokeColor(NSColor.systemBlue.cgColor)
            ctx.setLineWidth(1.4)
            ctx.strokeEllipse(in: knobRect)
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
