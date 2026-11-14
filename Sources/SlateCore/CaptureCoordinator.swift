import AppKit
import Carbon.HIToolbox
import Foundation
import UniformTypeIdentifiers

public final class CaptureOverlayWindow: NSWindow {
    public var onCancel: (() -> Void)?
    public override var canBecomeKey: Bool { true }
    public override var canBecomeMain: Bool { true }

    public override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        frameRect
    }

    public override func cancelOperation(_ sender: Any?) {
        onCancel?()
    }
}

public final class CaptureCoordinator {
    private let captureService = ScreenCaptureService()
    private let escapeHotkey = EscapeCancelHotkey()
    private var localKeyMonitor: Any?
    private var overlayWindows: [CaptureOverlayWindow] = []
    private var canvasViews: [CaptureCanvasView] = []
    private var isCapturing = false
    private var hudWindow: NSWindow?

    public var onError: ((Error) -> Void)?

    public init() {}

    @MainActor
    public func startCapture() {
        guard !isCapturing else { return }
        isCapturing = true

        Task { @MainActor [weak self] in
            guard let self = self else { return }
            do {
                let screens = try await self.captureService.captureAllScreens()
                self.presentOverlays(for: screens)
            } catch {
                self.isCapturing = false
                self.onError?(error)
            }
        }
    }

    @MainActor
    public func cancelCapture() {
        teardownOverlays()
    }

    @MainActor
    private func presentOverlays(for screens: [CapturedScreen]) {
        teardownOverlays(resetFlag: false)

        let mouseGlobal = NSEvent.mouseLocation
        var keyWindowCandidate: CaptureOverlayWindow?

        for captured in screens {
            let frame = captured.screen.frame
            let win = CaptureOverlayWindow(
                contentRect: frame,
                styleMask: [.borderless],
                backing: .buffered,
                defer: false
            )
            win.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.maximumWindow)))
            win.setFrame(frame, display: true)
            win.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
            win.isOpaque = false
            win.backgroundColor = .clear
            win.hasShadow = false
            win.ignoresMouseEvents = false
            win.acceptsMouseMovedEvents = true
            win.isReleasedWhenClosed = false

            let canvas = CaptureCanvasView(
                capturedScreen: captured,
                frame: NSRect(origin: .zero, size: frame.size)
            )
            canvas.updateInitialHover(globalMouseLocation: mouseGlobal)

            canvas.onBecameActiveScreen = { [weak self, weak canvas] in
                guard let self = self, let active = canvas else { return }
                for view in self.canvasViews where view !== active {
                    view.setInactiveOtherScreen(true)
                }
                active.setInactiveOtherScreen(false)
            }
            canvas.onCompleteWithCopy = { [weak self] image in
                self?.finishWithCopy(image: image, screen: captured.screen)
            }
            canvas.onCompleteWithSave = { [weak self] image in
                self?.finishWithSave(image: image)
            }
            canvas.onCancel = { [weak self] in
                self?.teardownOverlays()
            }
            canvas.onTextEditingChanged = { [weak self] editing in
                guard let self = self else { return }
                if editing {
                    self.escapeHotkey.unregister()
                } else if self.isCapturing {
                    self.escapeHotkey.register()
                }
            }
            win.onCancel = { [weak self] in
                self?.teardownOverlays()
            }

            win.contentView = canvas
            overlayWindows.append(win)
            canvasViews.append(canvas)

            if frame.contains(mouseGlobal) {
                keyWindowCandidate = win
            }
        }

        escapeHotkey.onEscape = { [weak self] in
            self?.handleEscapeCancel()
        }
        escapeHotkey.register()

        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self, self.isCapturing else { return event }
            if event.keyCode == UInt16(kVK_Escape), !self.canvasViews.contains(where: { $0.isTextEditingActive }) {
                self.teardownOverlays()
                return nil
            }
            return event
        }

        NSRunningApplication.current.activate(options: [.activateAllWindows])
        NSApp.activate()
        for win in overlayWindows {
            win.orderFrontRegardless()
        }
        if let keyWin = keyWindowCandidate ?? overlayWindows.first {
            keyWin.makeKeyAndOrderFront(nil)
            keyWin.makeFirstResponder(keyWin.contentView)
        }
    }

    @MainActor
    private func handleEscapeCancel() {
        guard isCapturing else { return }
        if canvasViews.contains(where: { $0.isTextEditingActive }) {
            return
        }
        teardownOverlays()
    }

    @MainActor
    private func teardownOverlays(resetFlag: Bool = true) {
        escapeHotkey.unregister()
        if let monitor = localKeyMonitor {
            NSEvent.removeMonitor(monitor)
            localKeyMonitor = nil
        }
        for win in overlayWindows {
            win.orderOut(nil)
            win.close()
        }
        overlayWindows.removeAll()
        canvasViews.removeAll()
        if resetFlag {
            isCapturing = false
        }
    }

    @MainActor
    private func finishWithCopy(image: CGImage, screen: NSScreen) {
        teardownOverlays()
        Self.copyToPasteboard(cgImage: image)
        showCopiedHUD(on: screen)
    }

    @MainActor
    private func finishWithSave(image: CGImage) {
        teardownOverlays()

        let panel = NSSavePanel()
        panel.title = "保存截图"
        panel.canCreateDirectories = true
        panel.allowedContentTypes = [.png, .jpeg]
        panel.allowsOtherFileTypes = false
        panel.nameFieldStringValue = Self.defaultFilename()

        NSApp.activate(ignoringOtherApps: true)
        let response = panel.runModal()
        guard response == .OK, let url = panel.url else { return }

        let ext = url.pathExtension.lowercased()
        let data: Data?
        if ext == "jpg" || ext == "jpeg" {
            data = AnnotationRenderer.jpegData(from: image)
        } else {
            data = AnnotationRenderer.pngData(from: image)
        }

        if let data = data {
            do {
                try data.write(to: url, options: .atomic)
            } catch {
                onError?(error)
            }
        }
    }

    public static func copyToPasteboard(cgImage: CGImage) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()

        let nsImage = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
        if let pngData = AnnotationRenderer.pngData(from: cgImage) {
            pasteboard.declareTypes([.png, .tiff], owner: nil)
            pasteboard.setData(pngData, forType: .png)
            if let tiffData = nsImage.tiffRepresentation {
                pasteboard.setData(tiffData, forType: .tiff)
            }
        } else {
            pasteboard.writeObjects([nsImage])
        }
    }

    public static func defaultFilename(date: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        return "Slate_\(formatter.string(from: date)).png"
    }

    @MainActor
    private func showCopiedHUD(on screen: NSScreen) {
        hudWindow?.orderOut(nil)
        hudWindow = nil

        let size = NSSize(width: 168, height: 38)
        let origin = NSPoint(
            x: screen.frame.midX - size.width * 0.5,
            y: screen.visibleFrame.minY + 64
        )
        let win = NSWindow(
            contentRect: NSRect(origin: origin, size: size),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        win.level = .floating
        win.isOpaque = false
        win.backgroundColor = .clear
        win.ignoresMouseEvents = true
        win.hasShadow = true

        let effect = NSVisualEffectView(frame: NSRect(origin: .zero, size: size))
        effect.material = .hudWindow
        effect.state = .active
        effect.appearance = NSAppearance(named: .darkAqua)
        effect.wantsLayer = true
        effect.layer?.cornerRadius = 19
        effect.layer?.masksToBounds = true

        let label = NSTextField(labelWithString: "✓ 已复制到剪贴板")
        label.font = .systemFont(ofSize: 13, weight: .medium)
        label.textColor = .white
        label.alignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        effect.addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: effect.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: effect.centerYAnchor)
        ])

        win.contentView = effect
        win.alphaValue = 1.0
        win.orderFrontRegardless()
        hudWindow = win

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) { [weak self, weak win] in
            guard let win = win else { return }
            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = 0.25
                win.animator().alphaValue = 0.0
            }, completionHandler: {
                win.orderOut(nil)
                if self?.hudWindow === win {
                    self?.hudWindow = nil
                }
            })
        }
    }
}
