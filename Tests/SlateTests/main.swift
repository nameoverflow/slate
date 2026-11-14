import AppKit
import Carbon.HIToolbox
import Foundation
import SlateCore

private var failureCount = 0

private func check(_ condition: Bool, _ message: String, file: String = #file, line: Int = #line) {
    if !condition {
        fputs("FAIL [\(file):\(line)]: \(message)\n", stderr)
        failureCount += 1
    }
}

private func checkEqual<T: Equatable>(_ a: T, _ b: T, _ message: String = "", file: String = #file, line: Int = #line) {
    if a != b {
        fputs("FAIL [\(file):\(line)]: \(message) expected \(b), got \(a)\n", stderr)
        failureCount += 1
    }
}

private func makeDummyCGImage(pxW: Int, pxH: Int) -> CGImage {
    let cs = CGColorSpace(name: CGColorSpace.sRGB)!
    let ctx = CGContext(
        data: nil,
        width: pxW,
        height: pxH,
        bitsPerComponent: 8,
        bytesPerRow: pxW * 4,
        space: cs,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
    )!
    ctx.setFillColor(NSColor.black.cgColor)
    ctx.fill(CGRect(x: 0, y: 0, width: pxW, height: pxH))
    return ctx.makeImage()!
}

// MARK: - Tests

func testCGRectToAppKitConversion() {
    let primaryHeight: CGFloat = 1000
    let topLeftCG = CGRect(x: 100, y: 50, width: 400, height: 300)
    let appKit = WindowCoordinateHelper.cgRectToAppKit(topLeftCG, primaryScreenHeight: primaryHeight)
    checkEqual(appKit, CGRect(x: 100, y: 650, width: 400, height: 300), "Primary conversion")

    let upperMonitorWin = CGRect(x: 0, y: -1080, width: 500, height: 200)
    let upperAppKit = WindowCoordinateHelper.cgRectToAppKit(upperMonitorWin, primaryScreenHeight: primaryHeight)
    checkEqual(upperAppKit, CGRect(x: 0, y: 1880, width: 500, height: 200), "Upper monitor conversion")
}

func testFilterAndHitTestWindowsFrontToBack() {
    let ownPID: pid_t = 999
    let primaryH: CGFloat = 900
    let raw: [[String: Any]] = [
        [
            kCGWindowOwnerPID as String: ownPID,
            kCGWindowOwnerName as String: "Slate",
            kCGWindowLayer as String: 0,
            kCGWindowAlpha as String: 1.0,
            kCGWindowNumber as String: CGWindowID(1),
            kCGWindowBounds as String: ["X": 0.0, "Y": 0.0, "Width": 500.0, "Height": 500.0]
        ],
        [
            kCGWindowOwnerPID as String: pid_t(10),
            kCGWindowOwnerName as String: "Window Server",
            kCGWindowLayer as String: 24,
            kCGWindowAlpha as String: 1.0,
            kCGWindowNumber as String: CGWindowID(2),
            kCGWindowBounds as String: ["X": 0.0, "Y": 0.0, "Width": 1440.0, "Height": 32.0]
        ],
        [
            kCGWindowOwnerPID as String: pid_t(200),
            kCGWindowOwnerName as String: "Notes",
            kCGWindowLayer as String: 0,
            kCGWindowAlpha as String: 1.0,
            kCGWindowNumber as String: CGWindowID(3),
            kCGWindowBounds as String: ["X": 100.0, "Y": 100.0, "Width": 400.0, "Height": 300.0]
        ],
        [
            kCGWindowOwnerPID as String: pid_t(201),
            kCGWindowOwnerName as String: "Safari",
            kCGWindowLayer as String: 0,
            kCGWindowAlpha as String: 1.0,
            kCGWindowNumber as String: CGWindowID(4),
            kCGWindowBounds as String: ["X": 50.0, "Y": 50.0, "Width": 800.0, "Height": 600.0]
        ]
    ]

    let filtered = WindowCoordinateHelper.filterWindowDictionaries(
        raw,
        ownPID: ownPID,
        primaryScreenHeight: primaryH
    )
    checkEqual(filtered.count, 2, "Filtered count")
    checkEqual(filtered[0].ownerName, "Notes", "Frontmost owner")
    checkEqual(filtered[1].ownerName, "Safari", "Back owner")

    let screenFrame = CGRect(x: 0, y: 0, width: 1440, height: 900)
    let localWins = WindowCoordinateHelper.localWindows(from: filtered, forScreenFrame: screenFrame)

    let hitFront = WindowCoordinateHelper.hitTestLocalWindow(
        atLocalPoint: CGPoint(x: 200, y: 600),
        localWindows: localWins
    )
    checkEqual(hitFront, CGRect(x: 100, y: 500, width: 400, height: 300), "Front hit")

    let hitBack = WindowCoordinateHelper.hitTestLocalWindow(
        atLocalPoint: CGPoint(x: 70, y: 600),
        localWindows: localWins
    )
    checkEqual(hitBack, CGRect(x: 50, y: 250, width: 800, height: 600), "Back hit")

    let hitNone = WindowCoordinateHelper.hitTestLocalWindow(
        atLocalPoint: CGPoint(x: 1200, y: 100),
        localWindows: localWins
    )
    check(hitNone == nil, "Miss returns nil")
}

func testSelectionGeometryResizeAndClamp() {
    let bounds = CGRect(x: 0, y: 0, width: 1000, height: 800)
    let initial = CGRect(x: 200, y: 200, width: 300, height: 200)

    let resized = SelectionGeometry.resizedRect(
        from: initial,
        handle: .topRight,
        to: CGPoint(x: 1200, y: 900),
        bounds: bounds
    )
    checkEqual(resized, CGRect(x: 200, y: 200, width: 800, height: 600), "Clamped resize")

    let minClamped = SelectionGeometry.resizedRect(
        from: initial,
        handle: .bottomLeft,
        to: CGPoint(x: 600, y: 600),
        bounds: bounds,
        minSize: 20
    )
    checkEqual(minClamped.width, 20, "Min width")
    checkEqual(minClamped.height, 20, "Min height")
}

func testToolbarPlacementFallbacks() {
    let bounds = CGRect(x: 0, y: 0, width: 1200, height: 800)
    let size = CGSize(width: 398, height: 40)

    let midSel = CGRect(x: 300, y: 300, width: 500, height: 300)
    let belowFrame = FloatingToolbarView.preferredFrame(forSize: size, selectionRect: midSel, bounds: bounds)
    check(belowFrame.maxY < midSel.minY, "Normal selection puts toolbar below")

    let bottomSel = CGRect(x: 300, y: 5, width: 500, height: 200)
    let aboveFrame = FloatingToolbarView.preferredFrame(forSize: size, selectionRect: bottomSel, bounds: bounds)
    check(aboveFrame.minY > bottomSel.maxY, "Bottom-edge selection puts toolbar above")

    let fullFrame = FloatingToolbarView.preferredFrame(forSize: size, selectionRect: bounds, bounds: bounds)
    check(fullFrame.minY >= bounds.minY + 10 && fullFrame.maxY <= bounds.maxY, "Fullscreen places inside bottom")
}

func testRetinaRenderFinalImageWithAnnotations() {
    let baseImage = makeDummyCGImage(pxW: 400, pxH: 200)
    let viewBounds = CGRect(x: 0, y: 0, width: 200, height: 100)
    let selectionRect = CGRect(x: 50, y: 25, width: 100, height: 50)
    let annotations: [AnnotationItem] = [
        AnnotationItem(
            kind: .rectangle(CGRect(x: 60, y: 35, width: 80, height: 30)),
            color: NSColor(srgbRed: 1, green: 0, blue: 0, alpha: 1),
            lineWidth: 4
        ),
        AnnotationItem(
            kind: .ellipse(CGRect(x: 70, y: 40, width: 40, height: 20)),
            color: NSColor(srgbRed: 0, green: 1, blue: 0, alpha: 1),
            lineWidth: 3
        ),
        AnnotationItem(
            kind: .arrow(start: CGPoint(x: 55, y: 30), end: CGPoint(x: 140, y: 70)),
            color: NSColor(srgbRed: 0, green: 0, blue: 1, alpha: 1),
            lineWidth: 3
        ),
        AnnotationItem(
            kind: .brush([CGPoint(x: 60, y: 50), CGPoint(x: 80, y: 55), CGPoint(x: 100, y: 45)]),
            color: NSColor.white,
            lineWidth: 3
        ),
        AnnotationItem(
            kind: .text(rect: CGRect(x: 65, y: 38, width: 70, height: 24), string: "测试", fontSize: 16),
            color: NSColor.yellow,
            lineWidth: 3
        )
    ]

    guard let output = AnnotationRenderer.renderFinalImage(
        baseImage: baseImage,
        viewBounds: viewBounds,
        selectionRect: selectionRect,
        annotations: annotations
    ) else {
        check(false, "renderFinalImage returned nil")
        return
    }
    checkEqual(output.width, 200, "Output pixel width")
    checkEqual(output.height, 100, "Output pixel height")

    let png = AnnotationRenderer.pngData(from: output)
    check((png?.count ?? 0) > 100, "PNG data generated")
    let jpeg = AnnotationRenderer.jpegData(from: output)
    check((jpeg?.count ?? 0) > 100, "JPEG data generated")
}

func testHotkeyComboDisplayString() {
    let combo = HotkeyCombo(keyCode: UInt32(kVK_ANSI_A), carbonModifiers: UInt32(controlKey | shiftKey))
    checkEqual(combo.displayString, "⌃⇧A", "Hotkey display string")
}

func testCanvasClickWindowAndDoubleClickCopy() {
    guard let screen = NSScreen.screens.first else {
        check(false, "Need at least one NSScreen for canvas test")
        return
    }
    let boundsSize = NSSize(width: 800, height: 600)
    let winRect = CGRect(x: 100, y: 100, width: 300, height: 200)
    let captured = CapturedScreen(
        screen: screen,
        displayID: CGMainDisplayID(),
        image: makeDummyCGImage(pxW: 1600, pxH: 1200),
        localWindows: [winRect]
    )

    let window = NSWindow(
        contentRect: NSRect(origin: .zero, size: boundsSize),
        styleMask: [.borderless],
        backing: .buffered,
        defer: false
    )
    let canvas = CaptureCanvasView(capturedScreen: captured, frame: NSRect(origin: .zero, size: boundsSize))
    window.contentView = canvas

    var copiedImage: CGImage?
    canvas.onCompleteWithCopy = { img in copiedImage = img }

    // Simulate mouse moved into winRect -> click -> should enter editing phase
    let moveEvt = NSEvent.mouseEvent(
        with: .mouseMoved, location: CGPoint(x: 200, y: 200), modifierFlags: [],
        timestamp: 0, windowNumber: window.windowNumber, context: nil, eventNumber: 1, clickCount: 0, pressure: 0
    )!
    canvas.mouseMoved(with: moveEvt)

    let downEvt = NSEvent.mouseEvent(
        with: .leftMouseDown, location: CGPoint(x: 200, y: 200), modifierFlags: [],
        timestamp: 0.1, windowNumber: window.windowNumber, context: nil, eventNumber: 2, clickCount: 1, pressure: 1
    )!
    let upEvt = NSEvent.mouseEvent(
        with: .leftMouseUp, location: CGPoint(x: 200, y: 200), modifierFlags: [],
        timestamp: 0.15, windowNumber: window.windowNumber, context: nil, eventNumber: 3, clickCount: 1, pressure: 0
    )!
    canvas.mouseDown(with: downEvt)
    canvas.mouseUp(with: upEvt)
    check(canvas.phase == .editing, "Click inside hovered window enters editing phase")

    // Double-click inside selected window -> should trigger copy with exact 2x pixel dimensions (600x400)
    let dblClickEvt = NSEvent.mouseEvent(
        with: .leftMouseDown, location: CGPoint(x: 210, y: 210), modifierFlags: [],
        timestamp: 0.3, windowNumber: window.windowNumber, context: nil, eventNumber: 4, clickCount: 2, pressure: 1
    )!
    canvas.mouseDown(with: dblClickEvt)
    check(copiedImage != nil, "Double-click triggers copy")
    checkEqual(copiedImage?.width, 600, "Copied window width in 2x pixels")
    checkEqual(copiedImage?.height, 400, "Copied window height in 2x pixels")
}

func testCanvasDragCustomRectAndEnterCopy() {
    guard let screen = NSScreen.screens.first else {
        check(false, "Need at least one NSScreen for canvas test")
        return
    }
    let boundsSize = NSSize(width: 800, height: 600)
    let captured = CapturedScreen(
        screen: screen,
        displayID: CGMainDisplayID(),
        image: makeDummyCGImage(pxW: 1600, pxH: 1200),
        localWindows: [CGRect(x: 0, y: 0, width: 800, height: 600)]
    )

    let window = NSWindow(
        contentRect: NSRect(origin: .zero, size: boundsSize),
        styleMask: [.borderless],
        backing: .buffered,
        defer: false
    )
    let canvas = CaptureCanvasView(capturedScreen: captured, frame: NSRect(origin: .zero, size: boundsSize))
    window.contentView = canvas

    var copiedImage: CGImage?
    canvas.onCompleteWithCopy = { img in copiedImage = img }

    let downEvt = NSEvent.mouseEvent(
        with: .leftMouseDown, location: CGPoint(x: 50, y: 50), modifierFlags: [],
        timestamp: 0.1, windowNumber: window.windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: 1
    )!
    let dragEvt = NSEvent.mouseEvent(
        with: .leftMouseDragged, location: CGPoint(x: 250, y: 150), modifierFlags: [],
        timestamp: 0.2, windowNumber: window.windowNumber, context: nil, eventNumber: 2, clickCount: 1, pressure: 1
    )!
    let upEvt = NSEvent.mouseEvent(
        with: .leftMouseUp, location: CGPoint(x: 250, y: 150), modifierFlags: [],
        timestamp: 0.25, windowNumber: window.windowNumber, context: nil, eventNumber: 3, clickCount: 1, pressure: 0
    )!
    canvas.mouseDown(with: downEvt)
    canvas.mouseDragged(with: dragEvt)
    canvas.mouseUp(with: upEvt)
    check(canvas.phase == .editing, "Drag draws custom rect and enters editing phase")

    let enterEvt = NSEvent.keyEvent(
        with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0.3,
        windowNumber: window.windowNumber, context: nil, characters: "\r",
        charactersIgnoringModifiers: "\r", isARepeat: false, keyCode: UInt16(kVK_Return)
    )!
    canvas.keyDown(with: enterEvt)
    check(copiedImage != nil, "Enter triggers copy")
    checkEqual(copiedImage?.width, 400, "Dragged rect width in 2x pixels (200pt * 2)")
    checkEqual(copiedImage?.height, 200, "Dragged rect height in 2x pixels (100pt * 2)")
}

func testToolbarButtonDimensionsAndSnapshot(outputPath: String? = nil) {
    let toolbar = FloatingToolbarView(frame: .zero)
    toolbar.setTool(.rectangle)
    let size = toolbar.requiredSize()
    let win = NSWindow(
        contentRect: NSRect(origin: .zero, size: CGSize(width: size.width + 40, height: size.height + 40)),
        styleMask: [.borderless],
        backing: .buffered,
        defer: false
    )
    win.backgroundColor = NSColor(srgbRed: 0.2, green: 0.22, blue: 0.25, alpha: 1.0)
    toolbar.frame = NSRect(origin: CGPoint(x: 20, y: 20), size: size)
    win.contentView?.addSubview(toolbar)
    win.layoutIfNeeded()
    toolbar.layoutSubtreeIfNeeded()

    // Verify all icon buttons inside the main stack remain exact 28x28 and copy button 64x28.
    let frames = toolbar.mainButtonFramesForTesting
    checkEqual(frames.count, 9, "Main toolbar has 9 buttons (5 tools + undo + save + cancel + copy)")
    for (name, btnSize) in frames {
        if name == "copy" {
            checkEqual(btnSize, CGSize(width: 64, height: 28), "Copy button size")
        } else {
            checkEqual(btnSize, CGSize(width: 28, height: 28), "Icon button \(name) size")
        }
    }

    if let path = outputPath, let view = win.contentView,
       let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
        view.cacheDisplay(in: view.bounds, to: rep)
        if let data = rep.representation(using: .png, properties: [:]) {
            try? data.write(to: URL(fileURLWithPath: path))
        }
    }
}

func testLaunchAtLoginManagerEnableDisable() throws {
    let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("slate_test_\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: tempDir) }

    let plistURL = tempDir.appendingPathComponent("LaunchAgents/com.slate.screenshot.plist")
    let manager = LaunchAtLoginManager(plistURL: plistURL)
    check(!manager.isEnabled, "Initially disabled")

    try manager.setEnabled(true, executablePath: "/Applications/Slate.app/Contents/MacOS/Slate")
    check(manager.isEnabled, "Enabled after setEnabled(true)")
    check(FileManager.default.fileExists(atPath: plistURL.path), "Plist written")

    let data = try Data(contentsOf: plistURL)
    let dict = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
    checkEqual(dict?["Label"] as? String, "com.slate.screenshot", "Plist label")
    checkEqual(dict?["ProgramArguments"] as? [String], ["/Applications/Slate.app/Contents/MacOS/Slate"], "Plist exec")
    checkEqual(dict?["RunAtLoad"] as? Bool, true, "Plist RunAtLoad")
    checkEqual(dict?["KeepAlive"] as? Bool, false, "Plist KeepAlive")

    try manager.setEnabled(false)
    check(!manager.isEnabled, "Disabled after setEnabled(false)")
    check(!FileManager.default.fileExists(atPath: plistURL.path), "Plist removed")
}

func testCanvasEscapeCancelsInSelectingAndEditing() {
    guard let screen = NSScreen.screens.first else {
        check(false, "Need at least one NSScreen for Escape test")
        return
    }
    let boundsSize = NSSize(width: 800, height: 600)
    let winRect = CGRect(x: 100, y: 100, width: 300, height: 200)
    let captured = CapturedScreen(
        screen: screen,
        displayID: CGMainDisplayID(),
        image: makeDummyCGImage(pxW: 1600, pxH: 1200),
        localWindows: [winRect]
    )

    let window = CaptureOverlayWindow(
        contentRect: NSRect(origin: .zero, size: boundsSize),
        styleMask: [.borderless],
        backing: .buffered,
        defer: false
    )
    let canvas = CaptureCanvasView(capturedScreen: captured, frame: NSRect(origin: .zero, size: boundsSize))
    window.contentView = canvas

    var cancelCount = 0
    canvas.onCancel = { cancelCount += 1 }
    window.onCancel = { cancelCount += 1 }

    // 1. Esc via keyDown during .selecting
    let escEvt = NSEvent.keyEvent(
        with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0.1,
        windowNumber: window.windowNumber, context: nil, characters: "\u{1b}",
        charactersIgnoringModifiers: "\u{1b}", isARepeat: false, keyCode: UInt16(kVK_Escape)
    )!
    canvas.keyDown(with: escEvt)
    checkEqual(cancelCount, 1, "Esc keyDown cancels in selecting phase")

    // 2. Esc via cancelOperation during .editing
    let moveEvt = NSEvent.mouseEvent(
        with: .mouseMoved, location: CGPoint(x: 200, y: 200), modifierFlags: [],
        timestamp: 0.2, windowNumber: window.windowNumber, context: nil, eventNumber: 1, clickCount: 0, pressure: 0
    )!
    let downEvt = NSEvent.mouseEvent(
        with: .leftMouseDown, location: CGPoint(x: 200, y: 200), modifierFlags: [],
        timestamp: 0.25, windowNumber: window.windowNumber, context: nil, eventNumber: 2, clickCount: 1, pressure: 1
    )!
    let upEvt = NSEvent.mouseEvent(
        with: .leftMouseUp, location: CGPoint(x: 200, y: 200), modifierFlags: [],
        timestamp: 0.3, windowNumber: window.windowNumber, context: nil, eventNumber: 3, clickCount: 1, pressure: 0
    )!
    canvas.mouseMoved(with: moveEvt)
    canvas.mouseDown(with: downEvt)
    canvas.mouseUp(with: upEvt)
    check(canvas.phase == .editing, "Entered editing phase")

    canvas.cancelOperation(nil)
    checkEqual(cancelCount, 2, "cancelOperation cancels in editing phase")
}

func testCanvasTopEdgeSelectionAndFirstMouse() {
    guard let screen = NSScreen.screens.first else {
        check(false, "Need at least one NSScreen for top-edge test")
        return
    }
    let boundsSize = NSSize(width: 800, height: 600)
    let fullWinRect = CGRect(x: 0, y: 0, width: 800, height: 600)
    let captured = CapturedScreen(
        screen: screen,
        displayID: CGMainDisplayID(),
        image: makeDummyCGImage(pxW: 1600, pxH: 1200),
        localWindows: [fullWinRect]
    )

    let window = CaptureOverlayWindow(
        contentRect: NSRect(origin: .zero, size: boundsSize),
        styleMask: [.borderless],
        backing: .buffered,
        defer: false
    )
    let canvas = CaptureCanvasView(capturedScreen: captured, frame: NSRect(origin: .zero, size: boundsSize))
    window.contentView = canvas

    check(canvas.acceptsFirstMouse(for: nil), "Canvas accepts first mouse click immediately")
    check(canvas.hitTest(NSPoint(x: 400, y: 600)) === canvas, "hitTest at exact top edge y=maxY hits canvas")
    check(canvas.hitTest(NSPoint(x: 800, y: 600)) === canvas, "hitTest at exact top-right corner hits canvas")

    // Dragging starting from exact top edge y=600 down to y=450 should enter editing phase and copy 200x150 (400x300 px)
    var copiedImage: CGImage?
    canvas.onCompleteWithCopy = { img in copiedImage = img }

    let downEvt = NSEvent.mouseEvent(
        with: .leftMouseDown, location: CGPoint(x: 100, y: 600), modifierFlags: [],
        timestamp: 0.1, windowNumber: window.windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: 1
    )!
    let dragEvt = NSEvent.mouseEvent(
        with: .leftMouseDragged, location: CGPoint(x: 300, y: 450), modifierFlags: [],
        timestamp: 0.2, windowNumber: window.windowNumber, context: nil, eventNumber: 2, clickCount: 1, pressure: 1
    )!
    let upEvt = NSEvent.mouseEvent(
        with: .leftMouseUp, location: CGPoint(x: 300, y: 450), modifierFlags: [],
        timestamp: 0.25, windowNumber: window.windowNumber, context: nil, eventNumber: 3, clickCount: 1, pressure: 0
    )!
    canvas.mouseDown(with: downEvt)
    canvas.mouseDragged(with: dragEvt)
    canvas.mouseUp(with: upEvt)
    check(canvas.phase == .editing, "Drag starting at top edge y=maxY enters editing phase")

    let enterEvt = NSEvent.keyEvent(
        with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0.3,
        windowNumber: window.windowNumber, context: nil, characters: "\r",
        charactersIgnoringModifiers: "\r", isARepeat: false, keyCode: UInt16(kVK_Return)
    )!
    canvas.keyDown(with: enterEvt)
    checkEqual(copiedImage?.width, 400, "Top-edge drag width in 2x pixels")
    checkEqual(copiedImage?.height, 300, "Top-edge drag height in 2x pixels")
}

// Initialize NSApplication for AppKit view tests
_ = NSApplication.shared

var renderPath: String?
if let idx = CommandLine.arguments.firstIndex(of: "--render-toolbar"), idx + 1 < CommandLine.arguments.count {
    renderPath = CommandLine.arguments[idx + 1]
}

testCGRectToAppKitConversion()
testFilterAndHitTestWindowsFrontToBack()
testSelectionGeometryResizeAndClamp()
testToolbarPlacementFallbacks()
testRetinaRenderFinalImageWithAnnotations()
testHotkeyComboDisplayString()
testCanvasClickWindowAndDoubleClickCopy()
testCanvasDragCustomRectAndEnterCopy()
testToolbarButtonDimensionsAndSnapshot(outputPath: renderPath)
testCanvasEscapeCancelsInSelectingAndEditing()
testCanvasTopEdgeSelectionAndFirstMouse()
do {
    try testLaunchAtLoginManagerEnableDisable()
} catch {
    check(false, "LaunchAtLoginManager test threw: \(error)")
}

if failureCount == 0 {
    print("All 12 SlateTests passed.")
    exit(0)
} else {
    fputs("\(failureCount) assertion(s) failed.\n", stderr)
    exit(1)
}
