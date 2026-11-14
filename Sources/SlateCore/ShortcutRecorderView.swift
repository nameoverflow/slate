import AppKit
import Carbon.HIToolbox
import Foundation

public final class ShortcutCaptureField: NSButton {
    public var isRecording = false {
        didSet { updateAppearance() }
    }
    public var combo: HotkeyCombo {
        didSet { updateAppearance() }
    }
    public var onBeginRecording: (() -> Void)?
    public var onCommitCombo: ((HotkeyCombo) -> Void)?
    public var onCancelRecording: (() -> Void)?

    private var localMonitor: Any?

    public init(combo: HotkeyCombo) {
        self.combo = combo
        super.init(frame: .zero)
        bezelStyle = .rounded
        font = NSFont.monospacedSystemFont(ofSize: 13, weight: .medium)
        target = self
        action = #selector(clicked)
        updateAppearance()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        stopMonitor()
    }

    @objc private func clicked() {
        if isRecording {
            cancelRecording()
        } else {
            startRecording()
        }
    }

    public func startRecording() {
        isRecording = true
        onBeginRecording?()
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            guard let self = self, self.isRecording else { return event }
            if event.keyCode == UInt16(kVK_Escape) {
                self.cancelRecording()
                return nil
            }
            let flags = event.modifierFlags.intersection([.command, .option, .control, .shift])
            let isFunctionKey = (event.keyCode >= UInt16(kVK_F1) && event.keyCode <= UInt16(kVK_F12))
            if flags.isEmpty && !isFunctionKey {
                NSSound.beep()
                return nil
            }
            let newCombo = HotkeyCombo(keyCode: event.keyCode, cocoaFlags: flags)
            self.stopMonitor()
            self.isRecording = false
            self.combo = newCombo
            self.onCommitCombo?(newCombo)
            return nil
        }
    }

    public func cancelRecording() {
        stopMonitor()
        if isRecording {
            isRecording = false
            onCancelRecording?()
        }
    }

    private func stopMonitor() {
        if let m = localMonitor {
            NSEvent.removeMonitor(m)
            localMonitor = nil
        }
    }

    private func updateAppearance() {
        if isRecording {
            title = "请按下新快捷键 (Esc 取消)"
            contentTintColor = .systemBlue
        } else {
            title = combo.displayString
            contentTintColor = nil
        }
    }
}

public final class PreferencesWindowController: NSWindowController, NSWindowDelegate {
    private let hotkeyManager: HotkeyManager
    private let launchManager: LaunchAtLoginManager
    private let recorderField: ShortcutCaptureField
    private let statusLabel = NSTextField(labelWithString: "")
    private let permissionLabel = NSTextField(labelWithString: "")
    private let launchAtLoginCheckbox = NSButton(checkboxWithTitle: "开机自启动（后台静默运行）", target: nil, action: nil)
    private let hideMenuIconCheckbox = NSButton(checkboxWithTitle: "隐藏菜单栏图标（纯快捷键触发）", target: nil, action: nil)

    private let onShortcutChanged: () -> Void
    private let onLaunchAtLoginToggled: (Bool) -> Void
    private let onHideMenuIconToggled: (Bool) -> Void
    private let onQuitRequested: () -> Void

    public init(
        hotkeyManager: HotkeyManager,
        launchManager: LaunchAtLoginManager,
        isMenuIconHidden: Bool,
        onShortcutChanged: @escaping () -> Void,
        onLaunchAtLoginToggled: @escaping (Bool) -> Void,
        onHideMenuIconToggled: @escaping (Bool) -> Void,
        onQuitRequested: @escaping () -> Void
    ) {
        self.hotkeyManager = hotkeyManager
        self.launchManager = launchManager
        self.recorderField = ShortcutCaptureField(combo: hotkeyManager.currentCombo)
        self.onShortcutChanged = onShortcutChanged
        self.onLaunchAtLoginToggled = onLaunchAtLoginToggled
        self.onHideMenuIconToggled = onHideMenuIconToggled
        self.onQuitRequested = onQuitRequested

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 292),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Slate 设置"
        window.isReleasedWhenClosed = false
        window.center()

        super.init(window: window)
        window.delegate = self
        setupUI(isMenuIconHidden: isMenuIconHidden)
        refreshState()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public func showAndActivate() {
        refreshState()
        recorderField.combo = hotkeyManager.currentCombo
        window?.center()
        showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    public func refreshState() {
        refreshPermissionStatus()
        launchAtLoginCheckbox.state = launchManager.isEnabled ? .on : .off
    }

    public func windowWillClose(_ notification: Notification) {
        recorderField.cancelRecording()
    }

    private func setupUI(isMenuIconHidden: Bool) {
        guard let contentView = window?.contentView else { return }

        let titleLabel = NSTextField(labelWithString: "全局截图快捷键")
        titleLabel.font = .systemFont(ofSize: 13, weight: .semibold)

        recorderField.onBeginRecording = { [weak self] in
            self?.hotkeyManager.unregister()
            self?.statusLabel.stringValue = "等待按键..."
            self?.statusLabel.textColor = .secondaryLabelColor
        }
        recorderField.onCancelRecording = { [weak self] in
            guard let self = self else { return }
            _ = self.hotkeyManager.registerCurrentCombo()
            self.statusLabel.stringValue = ""
        }
        recorderField.onCommitCombo = { [weak self] newCombo in
            guard let self = self else { return }
            if self.hotkeyManager.register(combo: newCombo) {
                self.statusLabel.stringValue = "已更新快捷键：\(newCombo.displayString)"
                self.statusLabel.textColor = .systemGreen
                self.onShortcutChanged()
            } else {
                _ = self.hotkeyManager.registerCurrentCombo()
                self.recorderField.combo = self.hotkeyManager.currentCombo
                self.statusLabel.stringValue = "注册失败（可能与系统快捷键冲突）"
                self.statusLabel.textColor = .systemRed
            }
        }

        let resetButton = NSButton(title: "恢复默认", target: self, action: #selector(resetDefault))
        resetButton.bezelStyle = .rounded

        let shortcutRow = NSStackView(views: [recorderField, resetButton])
        shortcutRow.orientation = .horizontal
        shortcutRow.spacing = 8

        statusLabel.font = .systemFont(ofSize: 11)
        statusLabel.textColor = .secondaryLabelColor

        let sep1 = NSBox()
        sep1.boxType = .separator

        launchAtLoginCheckbox.target = self
        launchAtLoginCheckbox.action = #selector(launchAtLoginClicked)

        hideMenuIconCheckbox.state = isMenuIconHidden ? .on : .off
        hideMenuIconCheckbox.target = self
        hideMenuIconCheckbox.action = #selector(hideMenuIconClicked)

        let hideHint = NSTextField(labelWithString: "隐藏菜单栏图标后，再次打开 Slate.app 即可呼出本设置窗口。")
        hideHint.font = .systemFont(ofSize: 11)
        hideHint.textColor = .secondaryLabelColor

        let sep2 = NSBox()
        sep2.boxType = .separator

        permissionLabel.font = .systemFont(ofSize: 12)
        let openSettingsButton = NSButton(title: "打开系统设置", target: self, action: #selector(openScreenRecordingSettings))
        openSettingsButton.bezelStyle = .rounded
        let quitButton = NSButton(title: "退出 Slate", target: self, action: #selector(quitClicked))
        quitButton.bezelStyle = .rounded

        let permRow = NSStackView(views: [permissionLabel, openSettingsButton, quitButton])
        permRow.orientation = .horizontal
        permRow.spacing = 8

        let hintLabel = NSTextField(labelWithString: "提示：点一下窗口直接框选；拖动可自定义矩形；双击或 Enter 复制。")
        hintLabel.font = .systemFont(ofSize: 11)
        hintLabel.textColor = .secondaryLabelColor
        hintLabel.maximumNumberOfLines = 2

        let stack = NSStackView(views: [
            titleLabel,
            shortcutRow,
            statusLabel,
            sep1,
            launchAtLoginCheckbox,
            hideMenuIconCheckbox,
            hideHint,
            sep2,
            permRow,
            hintLabel
        ])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false

        contentView.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 18),
            stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            recorderField.widthAnchor.constraint(greaterThanOrEqualToConstant: 210),
            sep1.widthAnchor.constraint(equalTo: stack.widthAnchor),
            sep2.widthAnchor.constraint(equalTo: stack.widthAnchor)
        ])
    }

    public func refreshPermissionStatus() {
        let granted = ScreenCaptureService.hasScreenRecordingPermission()
        if granted {
            permissionLabel.stringValue = "屏幕录制权限：已授权"
            permissionLabel.textColor = .systemGreen
        } else {
            permissionLabel.stringValue = "屏幕录制权限：未授权"
            permissionLabel.textColor = .systemOrange
        }
    }

    @objc private func resetDefault() {
        recorderField.cancelRecording()
        if hotkeyManager.register(combo: .defaultCombo) {
            recorderField.combo = .defaultCombo
            statusLabel.stringValue = "已恢复默认快捷键：\(HotkeyCombo.defaultCombo.displayString)"
            statusLabel.textColor = .secondaryLabelColor
            onShortcutChanged()
        }
    }

    @objc private func launchAtLoginClicked() {
        let enabled = (launchAtLoginCheckbox.state == .on)
        onLaunchAtLoginToggled(enabled)
        launchAtLoginCheckbox.state = launchManager.isEnabled ? .on : .off
    }

    @objc private func hideMenuIconClicked() {
        let hidden = (hideMenuIconCheckbox.state == .on)
        onHideMenuIconToggled(hidden)
    }

    @objc private func quitClicked() {
        onQuitRequested()
    }

    @objc private func openScreenRecordingSettings() {
        ScreenCaptureService.requestScreenRecordingPermission()
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }
}
