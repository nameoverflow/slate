import AppKit
import Carbon.HIToolbox
import Foundation

public enum CapturePhase: Equatable {
    case selecting
    case editing
}

public enum SelectionHandle: CaseIterable {
    case topLeft, top, topRight, right, bottomRight, bottom, bottomLeft, left
}

public enum SelectionGeometry {
    public static func normalizedRect(from a: CGPoint, to b: CGPoint) -> CGRect {
        CGRect(
            x: min(a.x, b.x),
            y: min(a.y, b.y),
            width: abs(b.x - a.x),
            height: abs(b.y - a.y)
        )
    }

    public static func clampPoint(_ pt: CGPoint, to rect: CGRect) -> CGPoint {
        CGPoint(
            x: max(rect.minX, min(pt.x, rect.maxX)),
            y: max(rect.minY, min(pt.y, rect.maxY))
        )
    }

    public static func handleCenter(_ handle: SelectionHandle, in rect: CGRect) -> CGPoint {
        switch handle {
        case .topLeft:     return CGPoint(x: rect.minX, y: rect.maxY)
        case .top:         return CGPoint(x: rect.midX, y: rect.maxY)
        case .topRight:    return CGPoint(x: rect.maxX, y: rect.maxY)
        case .right:       return CGPoint(x: rect.maxX, y: rect.midY)
        case .bottomRight: return CGPoint(x: rect.maxX, y: rect.minY)
        case .bottom:      return CGPoint(x: rect.midX, y: rect.minY)
        case .bottomLeft:  return CGPoint(x: rect.minX, y: rect.minY)
        case .left:        return CGPoint(x: rect.minX, y: rect.midY)
        }
    }

    public static func hitTestHandle(at point: CGPoint, in rect: CGRect, radius: CGFloat = 8) -> SelectionHandle? {
        for handle in SelectionHandle.allCases {
            let c = handleCenter(handle, in: rect)
            if hypot(point.x - c.x, point.y - c.y) <= radius {
                return handle
            }
        }
        return nil
    }

    public static func resizedRect(
        from initial: CGRect,
        handle: SelectionHandle,
        to point: CGPoint,
        bounds: CGRect,
        minSize: CGFloat = 12
    ) -> CGRect {
        let p = clampPoint(point, to: bounds)
        var minX = initial.minX
        var maxX = initial.maxX
        var minY = initial.minY
        var maxY = initial.maxY

        switch handle {
        case .topLeft:
            minX = min(p.x, maxX - minSize)
            maxY = max(p.y, minY + minSize)
        case .top:
            maxY = max(p.y, minY + minSize)
        case .topRight:
            maxX = max(p.x, minX + minSize)
            maxY = max(p.y, minY + minSize)
        case .right:
            maxX = max(p.x, minX + minSize)
        case .bottomRight:
            maxX = max(p.x, minX + minSize)
            minY = min(p.y, maxY - minSize)
        case .bottom:
            minY = min(p.y, maxY - minSize)
        case .bottomLeft:
            minX = min(p.x, maxX - minSize)
            minY = min(p.y, maxY - minSize)
        case .left:
            minX = min(p.x, maxX - minSize)
        }

        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }
}

private final class InlineAnnotationTextView: NSTextView {
    var onCommit: (() -> Void)?
    var onCancel: (() -> Void)?

    override func keyDown(with event: NSEvent) {
        if event.keyCode == UInt16(kVK_Escape) {
            onCancel?()
            return
        }
        if (event.keyCode == UInt16(kVK_Return) || event.keyCode == UInt16(kVK_ANSI_KeypadEnter))
            && !hasMarkedText()
            && !event.modifierFlags.contains(.shift) {
            onCommit?()
            return
        }
        super.keyDown(with: event)
    }
}

public final class CaptureCanvasView: NSView, NSTextViewDelegate {
    public let capturedScreen: CapturedScreen

    public var onBecameActiveScreen: (() -> Void)?
    public var onCompleteWithCopy: ((CGImage) -> Void)?
    public var onCompleteWithSave: ((CGImage) -> Void)?
    public var onCancel: (() -> Void)?
    public var onTextEditingChanged: ((Bool) -> Void)?

    public var isTextEditingActive: Bool { activeTextView != nil }

    public private(set) var phase: CapturePhase = .selecting
    private var isInactiveOtherScreen = false

    private var hoveredWindowRect: CGRect?
    private var selectionRect: CGRect = .zero

    // Selection drag state
    private var dragStartPoint: CGPoint = .zero
    private var candidateWindowRect: CGRect?
    private var isDraggingNewRect = false
    private var activeDragRect: CGRect?

    // Editing handle / move state
    private var activeHandle: SelectionHandle?
    private var initialRectBeforeResize: CGRect = .zero
    private var isMovingSelection = false
    private var moveOffset: CGPoint = .zero

    // Annotation state
    private var activeTool: AnnotationTool = .none
    private var currentColor: NSColor = AnnotationColorPalette.colors[0]
    private var currentThickness: StrokeThickness = .medium
    private var annotations: [AnnotationItem] = []
    private var inProgressAnnotation: AnnotationItem?
    private var drawStartPoint: CGPoint = .zero
    private var brushPoints: [CGPoint] = []

    // Inline text editor
    private var activeTextView: InlineAnnotationTextView?
    private var activeTextContainer: NSView?
    private var activeTextOrigin: CGPoint = .zero
    private var activeTextFontSize: CGFloat = 20

    private let toolbar = FloatingToolbarView(frame: .zero)
    private var trackingAreaRef: NSTrackingArea?

    public init(capturedScreen: CapturedScreen, frame: NSRect) {
        self.capturedScreen = capturedScreen
        super.init(frame: frame)
        wantsLayer = true
        setupToolbar()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public override var acceptsFirstResponder: Bool { true }

    public func setInactiveOtherScreen(_ inactive: Bool) {
        isInactiveOtherScreen = inactive
        if inactive && phase == .selecting {
            hoveredWindowRect = nil
        }
        needsDisplay = true
    }

    public func updateInitialHover(globalMouseLocation: CGPoint) {
        guard phase == .selecting else { return }
        let frame = capturedScreen.screen.frame
        if frame.contains(globalMouseLocation) {
            let local = CGPoint(
                x: globalMouseLocation.x - frame.origin.x,
                y: globalMouseLocation.y - frame.origin.y
            )
            hoveredWindowRect = WindowCoordinateHelper.hitTestLocalWindow(
                atLocalPoint: local,
                localWindows: capturedScreen.localWindows
            )
            needsDisplay = true
        }
    }

    public override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let existing = trackingAreaRef {
            removeTrackingArea(existing)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.activeAlways, .mouseMoved, .mouseEnteredAndExited, .cursorUpdate],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingAreaRef = area
    }

    public override func resetCursorRects() {
        discardCursorRects()
        if phase == .selecting {
            addCursorRect(bounds, cursor: .crosshair)
        } else {
            addCursorRect(bounds, cursor: .arrow)
        }
    }

    // MARK: - Toolbar Setup

    private func setupToolbar() {
        toolbar.isHidden = true
        toolbar.onSelectTool = { [weak self] tool in
            guard let self = self else { return }
            self.commitActiveTextIfNeeded()
            self.activeTool = tool
            self.repositionToolbar()
            self.window?.makeFirstResponder(self)
        }
        toolbar.onSelectColor = { [weak self] color in
            guard let self = self else { return }
            self.currentColor = color
            self.activeTextView?.textColor = color
            self.activeTextView?.insertionPointColor = color
        }
        toolbar.onSelectThickness = { [weak self] thickness in
            guard let self = self else { return }
            self.currentThickness = thickness
            if let tv = self.activeTextView {
                tv.font = .systemFont(ofSize: thickness.fontSize, weight: .semibold)
                self.activeTextFontSize = thickness.fontSize
                self.resizeActiveTextContainer()
            }
        }
        toolbar.onUndo = { [weak self] in
            self?.undoLastAnnotation()
        }
        toolbar.onSave = { [weak self] in
            self?.performSave()
        }
        toolbar.onCancel = { [weak self] in
            self?.onCancel?()
        }
        toolbar.onCopy = { [weak self] in
            self?.performCopy()
        }
        addSubview(toolbar)
    }

    private func repositionToolbar() {
        guard phase == .editing else {
            toolbar.isHidden = true
            return
        }
        let size = toolbar.requiredSize()
        toolbar.frame = FloatingToolbarView.preferredFrame(
            forSize: size,
            selectionRect: selectionRect,
            bounds: bounds
        )
        toolbar.isHidden = false
        toolbar.needsLayout = true
    }

    // MARK: - Drawing

    public override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }

        // 1. Draw the frozen screenshot across the full screen.
        ctx.draw(capturedScreen.image, in: bounds)

        // 2. Determine the active bright cutout rect.
        let brightRect: CGRect?
        switch phase {
        case .selecting:
            brightRect = isDraggingNewRect ? activeDragRect : hoveredWindowRect
        case .editing:
            brightRect = selectionRect
        }

        // 3. Draw semi-transparent dim overlay everywhere outside `brightRect`.
        ctx.saveGState()
        ctx.setFillColor(NSColor.black.withAlphaComponent(0.45).cgColor)
        let dimPath = CGMutablePath()
        dimPath.addRect(bounds)
        if let rect = brightRect, rect.width > 0, rect.height > 0 {
            dimPath.addRect(rect)
        }
        ctx.addPath(dimPath)
        ctx.fillPath(using: .evenOdd)
        ctx.restoreGState()

        // 4. Draw annotations clipped to `selectionRect` when editing.
        if phase == .editing {
            ctx.saveGState()
            ctx.clip(to: selectionRect)
            for item in annotations {
                AnnotationRenderer.draw(item, in: ctx)
            }
            if let current = inProgressAnnotation {
                AnnotationRenderer.draw(current, in: ctx)
            }
            ctx.restoreGState()
        }

        // 5. Draw border, handles, and dimension badge.
        if let rect = brightRect, rect.width > 0, rect.height > 0 {
            drawSelectionChrome(rect: rect, in: ctx)
        }
    }

    private func drawSelectionChrome(rect: CGRect, in ctx: CGContext) {
        ctx.saveGState()
        let borderColor = (phase == .selecting && !isDraggingNewRect)
            ? NSColor.systemBlue.withAlphaComponent(0.95)
            : NSColor.white.withAlphaComponent(0.92)
        ctx.setStrokeColor(borderColor.cgColor)
        ctx.setLineWidth(phase == .selecting && !isDraggingNewRect ? 2.5 : 1.5)
        ctx.stroke(rect.insetBy(dx: 0.5, dy: 0.5))

        if phase == .editing {
            let handleSize: CGFloat = 7
            for handle in SelectionHandle.allCases {
                let c = SelectionGeometry.handleCenter(handle, in: rect)
                let handleRect = CGRect(
                    x: c.x - handleSize * 0.5,
                    y: c.y - handleSize * 0.5,
                    width: handleSize,
                    height: handleSize
                )
                ctx.setFillColor(NSColor.white.cgColor)
                ctx.fillEllipse(in: handleRect)
                ctx.setStrokeColor(NSColor.systemBlue.cgColor)
                ctx.setLineWidth(1.2)
                ctx.strokeEllipse(in: handleRect)
            }
        }
        ctx.restoreGState()

        drawDimensionBadge(for: rect)
    }

    private func drawDimensionBadge(for rect: CGRect) {
        let w = Int(round(rect.width))
        let h = Int(round(rect.height))
        let label = "\(w) × \(h)"
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium),
            .foregroundColor: NSColor.white
        ]
        let textSize = (label as NSString).size(withAttributes: attrs)
        let padX: CGFloat = 7
        let padY: CGFloat = 3
        let badgeW = textSize.width + padX * 2
        let badgeH = textSize.height + padY * 2

        var badgeX = rect.minX
        badgeX = max(bounds.minX + 6, min(badgeX, bounds.maxX - badgeW - 6))
        var badgeY = rect.maxY + 6
        if badgeY + badgeH > bounds.maxY - 6 {
            badgeY = max(bounds.minY + 6, rect.maxY - badgeH - 6)
        }

        let badgeRect = CGRect(x: round(badgeX), y: round(badgeY), width: ceil(badgeW), height: ceil(badgeH))
        let bgPath = NSBezierPath(roundedRect: badgeRect, xRadius: 4, yRadius: 4)
        NSColor.black.withAlphaComponent(0.72).setFill()
        bgPath.fill()

        let textOrigin = CGPoint(x: badgeRect.minX + padX, y: badgeRect.minY + padY)
        (label as NSString).draw(at: textOrigin, withAttributes: attrs)
    }

    // MARK: - Mouse Handling

    public override func mouseMoved(with event: NSEvent) {
        let pt = convert(event.locationInWindow, from: nil)
        if phase == .selecting {
            if isInactiveOtherScreen { return }
            let hit = WindowCoordinateHelper.hitTestLocalWindow(
                atLocalPoint: pt,
                localWindows: capturedScreen.localWindows
            )
            if hit != hoveredWindowRect {
                hoveredWindowRect = hit
                needsDisplay = true
            }
            NSCursor.crosshair.set()
        } else {
            updateEditingCursor(at: pt)
        }
    }

    public override func mouseEntered(with event: NSEvent) {
        if phase == .selecting && !isInactiveOtherScreen {
            mouseMoved(with: event)
        }
    }

    public override func mouseExited(with event: NSEvent) {
        if phase == .selecting && hoveredWindowRect != nil {
            hoveredWindowRect = nil
            needsDisplay = true
        }
    }

    public override func mouseDown(with event: NSEvent) {
        let pt = convert(event.locationInWindow, from: nil)
        onBecameActiveScreen?()
        window?.makeFirstResponder(self)

        if phase == .selecting {
            dragStartPoint = pt
            candidateWindowRect = hoveredWindowRect
            isDraggingNewRect = false
            activeDragRect = nil
            return
        }

        // Phase == .editing
        if event.clickCount == 2 && selectionRect.contains(pt) {
            if let tv = activeTextView, let container = activeTextContainer,
               container.frame.contains(pt), !tv.string.isEmpty {
                return
            }
            cancelActiveTextIfNeeded()
            inProgressAnnotation = nil
            performCopy()
            return
        }

        if let container = activeTextContainer {
            if !container.frame.contains(pt) {
                commitActiveTextIfNeeded()
                return
            }
        }

        // Check resize handles first (even when an annotation tool is active).
        if let handle = SelectionGeometry.hitTestHandle(at: pt, in: selectionRect) {
            commitActiveTextIfNeeded()
            activeHandle = handle
            initialRectBeforeResize = selectionRect
            toolbar.isHidden = true
            return
        }

        guard selectionRect.contains(pt) else { return }

        if activeTool == .none {
            isMovingSelection = true
            moveOffset = CGPoint(x: pt.x - selectionRect.origin.x, y: pt.y - selectionRect.origin.y)
            toolbar.isHidden = true
            return
        }

        if activeTool == .text {
            beginTextInput(at: pt)
            return
        }

        // Start drawing shape / brush annotation
        drawStartPoint = pt
        switch activeTool {
        case .rectangle:
            inProgressAnnotation = AnnotationItem(
                kind: .rectangle(CGRect(origin: pt, size: .zero)),
                color: currentColor,
                lineWidth: currentThickness.lineWidth
            )
        case .ellipse:
            inProgressAnnotation = AnnotationItem(
                kind: .ellipse(CGRect(origin: pt, size: .zero)),
                color: currentColor,
                lineWidth: currentThickness.lineWidth
            )
        case .arrow:
            inProgressAnnotation = AnnotationItem(
                kind: .arrow(start: pt, end: pt),
                color: currentColor,
                lineWidth: currentThickness.lineWidth
            )
        case .brush:
            brushPoints = [pt]
            inProgressAnnotation = AnnotationItem(
                kind: .brush(brushPoints),
                color: currentColor,
                lineWidth: currentThickness.lineWidth
            )
        case .none, .text:
            break
        }
        needsDisplay = true
    }

    public override func mouseDragged(with event: NSEvent) {
        let pt = convert(event.locationInWindow, from: nil)

        if phase == .selecting {
            let clamped = SelectionGeometry.clampPoint(pt, to: bounds)
            if !isDraggingNewRect && hypot(pt.x - dragStartPoint.x, pt.y - dragStartPoint.y) > 4.0 {
                isDraggingNewRect = true
                hoveredWindowRect = nil
                candidateWindowRect = nil
            }
            if isDraggingNewRect {
                activeDragRect = SelectionGeometry.normalizedRect(from: dragStartPoint, to: clamped)
                needsDisplay = true
            }
            return
        }

        // Phase == .editing
        if let handle = activeHandle {
            selectionRect = SelectionGeometry.resizedRect(
                from: initialRectBeforeResize,
                handle: handle,
                to: pt,
                bounds: bounds
            )
            needsDisplay = true
            return
        }

        if isMovingSelection {
            var newOrigin = CGPoint(x: pt.x - moveOffset.x, y: pt.y - moveOffset.y)
            newOrigin.x = max(bounds.minX, min(newOrigin.x, bounds.maxX - selectionRect.width))
            newOrigin.y = max(bounds.minY, min(newOrigin.y, bounds.maxY - selectionRect.height))
            selectionRect.origin = newOrigin
            needsDisplay = true
            return
        }

        guard var current = inProgressAnnotation else { return }
        let clamped = SelectionGeometry.clampPoint(pt, to: selectionRect)
        let keepAspect = event.modifierFlags.contains(.shift)

        switch activeTool {
        case .rectangle:
            let endPt = keepAspect ? squareConstrainedPoint(from: drawStartPoint, to: clamped) : clamped
            current.kind = .rectangle(SelectionGeometry.normalizedRect(from: drawStartPoint, to: endPt))
        case .ellipse:
            let endPt = keepAspect ? squareConstrainedPoint(from: drawStartPoint, to: clamped) : clamped
            current.kind = .ellipse(SelectionGeometry.normalizedRect(from: drawStartPoint, to: endPt))
        case .arrow:
            let endPt = keepAspect ? angleSnappedPoint(from: drawStartPoint, to: clamped) : clamped
            current.kind = .arrow(start: drawStartPoint, end: endPt)
        case .brush:
            if let last = brushPoints.last, hypot(clamped.x - last.x, clamped.y - last.y) >= 1.5 {
                brushPoints.append(clamped)
                current.kind = .brush(brushPoints)
            }
        case .none, .text:
            break
        }
        inProgressAnnotation = current
        needsDisplay = true
    }

    public override func mouseUp(with event: NSEvent) {
        if phase == .selecting {
            if isDraggingNewRect {
                if let rect = activeDragRect, rect.width >= 6, rect.height >= 6 {
                    selectionRect = rect
                    enterEditingPhase()
                } else {
                    isDraggingNewRect = false
                    activeDragRect = nil
                    needsDisplay = true
                }
            } else {
                // Single click: auto-select hovered window.
                if let winRect = candidateWindowRect, winRect.width >= 6, winRect.height >= 6 {
                    selectionRect = winRect
                    enterEditingPhase()
                }
            }
            return
        }

        // Phase == .editing
        if activeHandle != nil {
            activeHandle = nil
            repositionToolbar()
            needsDisplay = true
            return
        }

        if isMovingSelection {
            isMovingSelection = false
            repositionToolbar()
            needsDisplay = true
            return
        }

        if let current = inProgressAnnotation {
            inProgressAnnotation = nil
            let shouldCommit: Bool
            switch current.kind {
            case .rectangle(let r), .ellipse(let r):
                shouldCommit = r.width >= 3 || r.height >= 3
            case .arrow(let s, let e):
                shouldCommit = hypot(e.x - s.x, e.y - s.y) >= 4
            case .brush(let pts):
                shouldCommit = !pts.isEmpty
            case .text:
                shouldCommit = false
            }
            if shouldCommit {
                annotations.append(current)
                toolbar.setCanUndo(!annotations.isEmpty)
            }
            needsDisplay = true
        }
    }

    // MARK: - Keyboard Handling

    public override func cancelOperation(_ sender: Any?) {
        if activeTextView != nil {
            cancelActiveTextIfNeeded()
        } else {
            onCancel?()
        }
    }

    public override func keyDown(with event: NSEvent) {
        if event.keyCode == UInt16(kVK_Escape) {
            if activeTextView != nil {
                cancelActiveTextIfNeeded()
                return
            }
            onCancel?()
            return
        }

        if phase == .editing {
            if event.keyCode == UInt16(kVK_Return) || event.keyCode == UInt16(kVK_ANSI_KeypadEnter) {
                performCopy()
                return
            }
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            if flags == .command {
                if event.charactersIgnoringModifiers?.lowercased() == "z" {
                    undoLastAnnotation()
                    return
                }
                if event.charactersIgnoringModifiers?.lowercased() == "s" {
                    performSave()
                    return
                }
                if event.charactersIgnoringModifiers?.lowercased() == "c" {
                    performCopy()
                    return
                }
            }
        }
        super.keyDown(with: event)
    }

    // MARK: - Inline Text Editing

    private func beginTextInput(at point: CGPoint) {
        commitActiveTextIfNeeded()

        let fontSize = currentThickness.fontSize
        let maxW = max(80, selectionRect.maxX - point.x - 6)
        let initW = min(220, maxW)
        let initH = fontSize + 14

        let originX = max(selectionRect.minX + 4, min(point.x, selectionRect.maxX - initW - 4))
        let originY = max(selectionRect.minY + 4, min(point.y - initH * 0.5, selectionRect.maxY - initH - 4))

        let container = NSView(frame: CGRect(x: originX, y: originY, width: initW, height: initH))
        container.wantsLayer = true
        container.layer?.borderColor = NSColor.white.withAlphaComponent(0.8).cgColor
        container.layer?.borderWidth = 1.0
        container.layer?.cornerRadius = 4
        container.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.25).cgColor

        let tv = InlineAnnotationTextView(frame: CGRect(x: 4, y: 2, width: initW - 8, height: initH - 4))
        tv.drawsBackground = false
        tv.isRichText = false
        tv.isFieldEditor = false
        tv.allowsUndo = true
        tv.font = .systemFont(ofSize: fontSize, weight: .semibold)
        tv.textColor = currentColor
        tv.insertionPointColor = currentColor
        tv.textContainer?.widthTracksTextView = true
        tv.textContainer?.lineFragmentPadding = 2
        tv.isVerticallyResizable = true
        tv.isHorizontallyResizable = false
        tv.delegate = self

        tv.onCommit = { [weak self] in
            self?.commitActiveTextIfNeeded()
        }
        tv.onCancel = { [weak self] in
            self?.cancelActiveTextIfNeeded()
        }

        container.addSubview(tv)
        addSubview(container, positioned: .below, relativeTo: toolbar)

        activeTextContainer = container
        activeTextView = tv
        activeTextOrigin = CGPoint(x: originX, y: originY)
        activeTextFontSize = fontSize
        onTextEditingChanged?(true)

        window?.makeFirstResponder(tv)
    }

    public func textDidChange(_ notification: Notification) {
        resizeActiveTextContainer()
    }

    private func resizeActiveTextContainer() {
        guard let tv = activeTextView, let container = activeTextContainer,
              let layoutManager = tv.layoutManager, let textContainer = tv.textContainer else { return }
        layoutManager.ensureLayout(for: textContainer)
        let used = layoutManager.usedRect(for: textContainer)
        let newH = max(activeTextFontSize + 14, ceil(used.height) + 10)
        var frame = container.frame
        let topY = frame.maxY
        frame.size.height = newH
        frame.origin.y = max(selectionRect.minY + 2, topY - newH)
        container.frame = frame
        tv.frame = CGRect(x: 4, y: 2, width: frame.width - 8, height: frame.height - 4)
    }

    private func commitActiveTextIfNeeded() {
        guard let tv = activeTextView, let container = activeTextContainer else { return }
        let text = tv.string.trimmingCharacters(in: .whitespacesAndNewlines)
        if !text.isEmpty {
            let textRect = CGRect(
                x: container.frame.minX + 6,
                y: container.frame.minY + 4,
                width: container.frame.width - 12,
                height: container.frame.height - 6
            )
            annotations.append(AnnotationItem(
                kind: .text(rect: textRect, string: tv.string, fontSize: activeTextFontSize),
                color: currentColor,
                lineWidth: currentThickness.lineWidth
            ))
            toolbar.setCanUndo(!annotations.isEmpty)
        }
        container.removeFromSuperview()
        activeTextView = nil
        activeTextContainer = nil
        onTextEditingChanged?(false)
        window?.makeFirstResponder(self)
        needsDisplay = true
    }

    private func cancelActiveTextIfNeeded() {
        let wasEditing = activeTextView != nil
        activeTextContainer?.removeFromSuperview()
        activeTextView = nil
        activeTextContainer = nil
        if wasEditing {
            onTextEditingChanged?(false)
        }
        window?.makeFirstResponder(self)
    }

    // MARK: - Actions & Helpers

    private func enterEditingPhase() {
        phase = .editing
        isDraggingNewRect = false
        activeDragRect = nil
        hoveredWindowRect = nil
        repositionToolbar()
        window?.invalidateCursorRects(for: self)
        needsDisplay = true
    }

    private func undoLastAnnotation() {
        if activeTextView != nil {
            cancelActiveTextIfNeeded()
            return
        }
        guard !annotations.isEmpty else { return }
        annotations.removeLast()
        toolbar.setCanUndo(!annotations.isEmpty)
        needsDisplay = true
    }

    private func renderSelectedCGImage() -> CGImage? {
        commitActiveTextIfNeeded()
        return AnnotationRenderer.renderFinalImage(
            baseImage: capturedScreen.image,
            viewBounds: bounds,
            selectionRect: selectionRect,
            annotations: annotations
        )
    }

    private func performCopy() {
        guard let image = renderSelectedCGImage() else { return }
        onCompleteWithCopy?(image)
    }

    private func performSave() {
        guard let image = renderSelectedCGImage() else { return }
        onCompleteWithSave?(image)
    }

    private func updateEditingCursor(at pt: CGPoint) {
        if let handle = SelectionGeometry.hitTestHandle(at: pt, in: selectionRect) {
            switch handle {
            case .top, .bottom: NSCursor.resizeUpDown.set()
            case .left, .right: NSCursor.resizeLeftRight.set()
            case .topLeft, .bottomRight, .topRight, .bottomLeft: NSCursor.crosshair.set()
            }
            return
        }
        if selectionRect.contains(pt) {
            if activeTool == .text {
                NSCursor.iBeam.set()
            } else if activeTool == .none {
                NSCursor.openHand.set()
            } else {
                NSCursor.crosshair.set()
            }
            return
        }
        NSCursor.arrow.set()
    }

    private func squareConstrainedPoint(from start: CGPoint, to end: CGPoint) -> CGPoint {
        let dx = end.x - start.x
        let dy = end.y - start.y
        let side = max(abs(dx), abs(dy))
        let candidate = CGPoint(
            x: start.x + (dx >= 0 ? side : -side),
            y: start.y + (dy >= 0 ? side : -side)
        )
        return SelectionGeometry.clampPoint(candidate, to: selectionRect)
    }

    private func angleSnappedPoint(from start: CGPoint, to end: CGPoint) -> CGPoint {
        let dx = end.x - start.x
        let dy = end.y - start.y
        let len = hypot(dx, dy)
        let angle = atan2(dy, dx)
        let snapped = round(angle / (.pi / 4)) * (.pi / 4)
        let candidate = CGPoint(x: start.x + cos(snapped) * len, y: start.y + sin(snapped) * len)
        return SelectionGeometry.clampPoint(candidate, to: selectionRect)
    }
}
