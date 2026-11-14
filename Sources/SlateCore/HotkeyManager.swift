import AppKit
import Carbon.HIToolbox
import Foundation

public struct HotkeyCombo: Codable, Equatable {
    public var keyCode: UInt32
    /// Carbon modifier mask (cmdKey, optionKey, controlKey, shiftKey).
    public var carbonModifiers: UInt32

    public static let defaultCombo = HotkeyCombo(
        keyCode: UInt32(kVK_ANSI_A),
        carbonModifiers: UInt32(controlKey | shiftKey)
    )

    public init(keyCode: UInt32, carbonModifiers: UInt32) {
        self.keyCode = keyCode
        self.carbonModifiers = carbonModifiers
    }

    public init(keyCode: UInt16, cocoaFlags: NSEvent.ModifierFlags) {
        self.keyCode = UInt32(keyCode)
        self.carbonModifiers = Self.carbonModifiers(from: cocoaFlags)
    }

    public static func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var result: UInt32 = 0
        if flags.contains(.control) { result |= UInt32(controlKey) }
        if flags.contains(.option) { result |= UInt32(optionKey) }
        if flags.contains(.shift) { result |= UInt32(shiftKey) }
        if flags.contains(.command) { result |= UInt32(cmdKey) }
        return result
    }

    public var displayString: String {
        var parts: [String] = []
        if (carbonModifiers & UInt32(controlKey)) != 0 { parts.append("⌃") }
        if (carbonModifiers & UInt32(optionKey)) != 0 { parts.append("⌥") }
        if (carbonModifiers & UInt32(shiftKey)) != 0 { parts.append("⇧") }
        if (carbonModifiers & UInt32(cmdKey)) != 0 { parts.append("⌘") }
        parts.append(Self.keyName(for: keyCode))
        return parts.joined()
    }

    public static func keyName(for keyCode: UInt32) -> String {
        let map: [UInt32: String] = [
            UInt32(kVK_ANSI_A): "A", UInt32(kVK_ANSI_B): "B", UInt32(kVK_ANSI_C): "C",
            UInt32(kVK_ANSI_D): "D", UInt32(kVK_ANSI_E): "E", UInt32(kVK_ANSI_F): "F",
            UInt32(kVK_ANSI_G): "G", UInt32(kVK_ANSI_H): "H", UInt32(kVK_ANSI_I): "I",
            UInt32(kVK_ANSI_J): "J", UInt32(kVK_ANSI_K): "K", UInt32(kVK_ANSI_L): "L",
            UInt32(kVK_ANSI_M): "M", UInt32(kVK_ANSI_N): "N", UInt32(kVK_ANSI_O): "O",
            UInt32(kVK_ANSI_P): "P", UInt32(kVK_ANSI_Q): "Q", UInt32(kVK_ANSI_R): "R",
            UInt32(kVK_ANSI_S): "S", UInt32(kVK_ANSI_T): "T", UInt32(kVK_ANSI_U): "U",
            UInt32(kVK_ANSI_V): "V", UInt32(kVK_ANSI_W): "W", UInt32(kVK_ANSI_X): "X",
            UInt32(kVK_ANSI_Y): "Y", UInt32(kVK_ANSI_Z): "Z",
            UInt32(kVK_ANSI_0): "0", UInt32(kVK_ANSI_1): "1", UInt32(kVK_ANSI_2): "2",
            UInt32(kVK_ANSI_3): "3", UInt32(kVK_ANSI_4): "4", UInt32(kVK_ANSI_5): "5",
            UInt32(kVK_ANSI_6): "6", UInt32(kVK_ANSI_7): "7", UInt32(kVK_ANSI_8): "8",
            UInt32(kVK_ANSI_9): "9",
            UInt32(kVK_F1): "F1", UInt32(kVK_F2): "F2", UInt32(kVK_F3): "F3",
            UInt32(kVK_F4): "F4", UInt32(kVK_F5): "F5", UInt32(kVK_F6): "F6",
            UInt32(kVK_F7): "F7", UInt32(kVK_F8): "F8", UInt32(kVK_F9): "F9",
            UInt32(kVK_F10): "F10", UInt32(kVK_F11): "F11", UInt32(kVK_F12): "F12",
            UInt32(kVK_Space): "Space",
            UInt32(kVK_ANSI_Minus): "-", UInt32(kVK_ANSI_Equal): "=",
            UInt32(kVK_ANSI_LeftBracket): "[", UInt32(kVK_ANSI_RightBracket): "]",
            UInt32(kVK_ANSI_Semicolon): ";", UInt32(kVK_ANSI_Quote): "'",
            UInt32(kVK_ANSI_Comma): ",", UInt32(kVK_ANSI_Period): ".",
            UInt32(kVK_ANSI_Slash): "/", UInt32(kVK_ANSI_Backslash): "\\",
            UInt32(kVK_ANSI_Grave): "`"
        ]
        return map[keyCode] ?? "Key(\(keyCode))"
    }
}

public final class HotkeyManager {
    private static let defaultsKey = "Slate.hotkeyCombo"
    private static let hotKeySignature: OSType = 0x534C5445 // 'SLTE'
    private static let hotKeyIDValue: UInt32 = 1

    private var eventHandlerRef: EventHandlerRef?
    private var hotKeyRef: EventHotKeyRef?

    public var onTrigger: (() -> Void)?
    public private(set) var currentCombo: HotkeyCombo

    public init() {
        self.currentCombo = Self.loadSavedCombo() ?? .defaultCombo
        installEventHandler()
    }

    deinit {
        unregister()
        if let handler = eventHandlerRef {
            RemoveEventHandler(handler)
        }
    }

    public func registerCurrentCombo() -> Bool {
        register(combo: currentCombo)
    }

    @discardableResult
    public func register(combo: HotkeyCombo) -> Bool {
        unregister()

        let hotKeyID = EventHotKeyID(signature: Self.hotKeySignature, id: Self.hotKeyIDValue)
        var newRef: EventHotKeyRef?
        let status = RegisterEventHotKey(
            combo.keyCode,
            combo.carbonModifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &newRef
        )
        guard status == noErr, let ref = newRef else {
            return false
        }
        hotKeyRef = ref
        currentCombo = combo
        Self.saveCombo(combo)
        return true
    }

    public func unregister() {
        if let ref = hotKeyRef {
            UnregisterEventHotKey(ref)
            hotKeyRef = nil
        }
    }

    private func installEventHandler() {
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let userData = Unmanaged.passUnretained(self).toOpaque()
        let callback: EventHandlerUPP = { _, event, userData in
            guard let userData = userData, let event = event else {
                return OSStatus(eventNotHandledErr)
            }
            var hotKeyID = EventHotKeyID()
            let err = GetEventParameter(
                event,
                EventParamName(kEventParamDirectObject),
                EventParamType(typeEventHotKeyID),
                nil,
                MemoryLayout<EventHotKeyID>.size,
                nil,
                &hotKeyID
            )
            if err == noErr && hotKeyID.signature == HotkeyManager.hotKeySignature && hotKeyID.id == HotkeyManager.hotKeyIDValue {
                let manager = Unmanaged<HotkeyManager>.fromOpaque(userData).takeUnretainedValue()
                DispatchQueue.main.async {
                    manager.onTrigger?()
                }
                return noErr
            }
            return OSStatus(eventNotHandledErr)
        }
        InstallEventHandler(GetApplicationEventTarget(), callback, 1, &eventType, userData, &eventHandlerRef)
    }

    private static func loadSavedCombo() -> HotkeyCombo? {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey) else { return nil }
        return try? JSONDecoder().decode(HotkeyCombo.self, from: data)
    }

    private static func saveCombo(_ combo: HotkeyCombo) {
        if let data = try? JSONEncoder().encode(combo) {
            UserDefaults.standard.set(data, forKey: defaultsKey)
        }
    }
}

/// Temporary global Escape hotkey used only while a capture overlay is visible.
public final class EscapeCancelHotkey {
    private static let signature: OSType = 0x534C5445 // 'SLTE'
    private static let idValue: UInt32 = 2

    private var eventHandlerRef: EventHandlerRef?
    private var hotKeyRef: EventHotKeyRef?
    public var onEscape: (() -> Void)?

    public init() {
        installEventHandler()
    }

    deinit {
        unregister()
        if let handler = eventHandlerRef {
            RemoveEventHandler(handler)
        }
    }

    public func register() {
        guard hotKeyRef == nil else { return }
        let hotKeyID = EventHotKeyID(signature: Self.signature, id: Self.idValue)
        var newRef: EventHotKeyRef?
        let status = RegisterEventHotKey(
            UInt32(kVK_Escape),
            0,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &newRef
        )
        if status == noErr {
            hotKeyRef = newRef
        }
    }

    public func unregister() {
        if let ref = hotKeyRef {
            UnregisterEventHotKey(ref)
            hotKeyRef = nil
        }
    }

    private func installEventHandler() {
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let userData = Unmanaged.passUnretained(self).toOpaque()
        let callback: EventHandlerUPP = { _, event, userData in
            guard let userData = userData, let event = event else {
                return OSStatus(eventNotHandledErr)
            }
            var hotKeyID = EventHotKeyID()
            let err = GetEventParameter(
                event,
                EventParamName(kEventParamDirectObject),
                EventParamType(typeEventHotKeyID),
                nil,
                MemoryLayout<EventHotKeyID>.size,
                nil,
                &hotKeyID
            )
            if err == noErr && hotKeyID.signature == EscapeCancelHotkey.signature && hotKeyID.id == EscapeCancelHotkey.idValue {
                let instance = Unmanaged<EscapeCancelHotkey>.fromOpaque(userData).takeUnretainedValue()
                DispatchQueue.main.async {
                    instance.onEscape?()
                }
                return noErr
            }
            return OSStatus(eventNotHandledErr)
        }
        InstallEventHandler(GetApplicationEventTarget(), callback, 1, &eventType, userData, &eventHandlerRef)
    }
}
