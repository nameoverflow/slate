import AppKit
import Foundation

public final class AppDelegate: NSObject, NSApplicationDelegate {
    private static let reopenNotificationName = Notification.Name("com.slate.screenshot.reopenPreferences")
    private static let hideMenuIconDefaultsKey = "Slate.hideStatusBarIcon"
    private static let launchConfiguredDefaultsKey = "Slate.launchAtLoginConfigured"
    private static let permissionPromptedDefaultsKey = "Slate.didPromptPermissionOnLaunch"

    private var statusItem: NSStatusItem!
    private var captureMenuItem: NSMenuItem!
    private var launchAtLoginMenuItem: NSMenuItem!
    private let hotkeyManager = HotkeyManager()
    private let launchManager = LaunchAtLoginManager()
    private let coordinator = CaptureCoordinator()
    private var preferencesController: PreferencesWindowController?

    private var isMenuIconHidden: Bool {
        get { UserDefaults.standard.bool(forKey: Self.hideMenuIconDefaultsKey) }
        set {
            UserDefaults.standard.set(newValue, forKey: Self.hideMenuIconDefaultsKey)
            statusItem.isVisible = !newValue
        }
    }

    public func applicationDidFinishLaunching(_ notification: Notification) {
        if !ensureSingleInstance() {
            NSApp.terminate(nil)
            return
        }

        setupMainMenu()
        configureDefaultLaunchAtLoginIfNeeded()
        setupStatusBar()
        observeReopenNotification()

        coordinator.onError = { [weak self] error in
            self?.presentErrorAlert(error)
        }

        hotkeyManager.onTrigger = { [weak self] in
            Task { @MainActor in
                self?.coordinator.startCapture()
            }
        }
        _ = hotkeyManager.registerCurrentCombo()

        if !ScreenCaptureService.hasScreenRecordingPermission()
            && !UserDefaults.standard.bool(forKey: Self.permissionPromptedDefaultsKey) {
            UserDefaults.standard.set(true, forKey: Self.permissionPromptedDefaultsKey)
            ScreenCaptureService.requestScreenRecordingPermission()
        }
    }

    public func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        openPreferences()
        return true
    }

    private func ensureSingleInstance() -> Bool {
        guard let bundleID = Bundle.main.bundleIdentifier else { return true }
        let ownPID = ProcessInfo.processInfo.processIdentifier
        let others = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
            .filter { $0.processIdentifier != ownPID }
        if !others.isEmpty {
            DistributedNotificationCenter.default().postNotificationName(
                Self.reopenNotificationName,
                object: bundleID,
                userInfo: nil,
                deliverImmediately: true
            )
            return false
        }
        return true
    }

    private func observeReopenNotification() {
        guard let bundleID = Bundle.main.bundleIdentifier else { return }
        DistributedNotificationCenter.default().addObserver(
            forName: Self.reopenNotificationName,
            object: bundleID,
            queue: .main
        ) { [weak self] _ in
            self?.openPreferences()
        }
    }

    private func configureDefaultLaunchAtLoginIfNeeded() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: Self.launchConfiguredDefaultsKey) else { return }
        if Bundle.main.bundlePath.hasPrefix("/Applications/") {
            try? launchManager.setEnabled(true)
            defaults.set(true, forKey: Self.launchConfiguredDefaultsKey)
        }
    }

    private func setupMainMenu() {
        let mainMenu = NSMenu()
        let editMenuItem = NSMenuItem()
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        editMenu.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        editMenu.addItem(NSMenuItem.separator())
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editMenuItem.submenu = editMenu
        mainMenu.addItem(editMenuItem)
        NSApp.mainMenu = mainMenu
    }

    private func setupStatusBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.isVisible = !isMenuIconHidden
        if let button = statusItem.button {
            if let img = NSImage(systemSymbolName: "camera.viewfinder", accessibilityDescription: "Slate") {
                img.isTemplate = true
                button.image = img
            } else {
                button.title = "截"
            }
            button.toolTip = "Slate 截屏 (\(hotkeyManager.currentCombo.displayString))"
        }

        let menu = NSMenu()
        captureMenuItem = NSMenuItem(
            title: "立即截图  \(hotkeyManager.currentCombo.displayString)",
            action: #selector(triggerCapture),
            keyEquivalent: ""
        )
        captureMenuItem.target = self
        menu.addItem(captureMenuItem)

        launchAtLoginMenuItem = NSMenuItem(
            title: "开机自启动",
            action: #selector(toggleLaunchAtLoginFromMenu),
            keyEquivalent: ""
        )
        launchAtLoginMenuItem.target = self
        launchAtLoginMenuItem.state = launchManager.isEnabled ? .on : .off
        menu.addItem(launchAtLoginMenuItem)

        let prefsItem = NSMenuItem(title: "快捷键与设置…", action: #selector(openPreferences), keyEquivalent: ",")
        prefsItem.target = self
        menu.addItem(prefsItem)

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(title: "退出 Slate", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
    }

    private func refreshMenuShortcutTitle() {
        let shortcut = hotkeyManager.currentCombo.displayString
        captureMenuItem.title = "立即截图  \(shortcut)"
        statusItem.button?.toolTip = "Slate 截屏 (\(shortcut))"
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        UserDefaults.standard.set(true, forKey: Self.launchConfiguredDefaultsKey)
        do {
            try launchManager.setEnabled(enabled)
        } catch {
            presentErrorAlert(error)
        }
        launchAtLoginMenuItem.state = launchManager.isEnabled ? .on : .off
        preferencesController?.refreshState()
    }

    @objc private func toggleLaunchAtLoginFromMenu() {
        setLaunchAtLogin(!launchManager.isEnabled)
    }

    @objc private func triggerCapture() {
        Task { @MainActor in
            coordinator.startCapture()
        }
    }

    @objc private func openPreferences() {
        if preferencesController == nil {
            preferencesController = PreferencesWindowController(
                hotkeyManager: hotkeyManager,
                launchManager: launchManager,
                isMenuIconHidden: isMenuIconHidden,
                onShortcutChanged: { [weak self] in
                    self?.refreshMenuShortcutTitle()
                },
                onLaunchAtLoginToggled: { [weak self] enabled in
                    self?.setLaunchAtLogin(enabled)
                },
                onHideMenuIconToggled: { [weak self] hidden in
                    self?.isMenuIconHidden = hidden
                },
                onQuitRequested: { [weak self] in
                    self?.quitApp()
                }
            )
        }
        preferencesController?.showAndActivate()
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }

    private func presentErrorAlert(_ error: Error) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Slate 提示"
        alert.informativeText = error.localizedDescription
        alert.alertStyle = .warning

        if case ScreenCaptureError.permissionDenied = error {
            alert.addButton(withTitle: "打开系统设置")
            alert.addButton(withTitle: "取消")
            if alert.runModal() == .alertFirstButtonReturn {
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
                    NSWorkspace.shared.open(url)
                }
            }
        } else {
            alert.addButton(withTitle: "确定")
            alert.runModal()
        }
    }
}
