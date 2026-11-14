import AppKit
import CoreGraphics
import Foundation
import ScreenCaptureKit

public struct WindowInfo: Equatable {
    public let windowID: CGWindowID
    public let ownerName: String
    public let layer: Int
    public let appKitBounds: CGRect

    public init(windowID: CGWindowID, ownerName: String, layer: Int, appKitBounds: CGRect) {
        self.windowID = windowID
        self.ownerName = ownerName
        self.layer = layer
        self.appKitBounds = appKitBounds
    }
}

public struct CapturedScreen {
    public let screen: NSScreen
    public let displayID: CGDirectDisplayID
    public let image: CGImage
    /// Window rects in view-local (AppKit bottom-left) coordinates, front-to-back order.
    public let localWindows: [CGRect]

    public init(screen: NSScreen, displayID: CGDirectDisplayID, image: CGImage, localWindows: [CGRect]) {
        self.screen = screen
        self.displayID = displayID
        self.image = image
        self.localWindows = localWindows
    }
}

public enum ScreenCaptureError: LocalizedError {
    case permissionDenied
    case noDisplaysFound
    case captureFailed(String)

    public var errorDescription: String? {
        switch self {
        case .permissionDenied:
            return "未获得屏幕录制权限，请在「系统设置 → 隐私与安全性 → 屏幕录制」中允许 Slate。"
        case .noDisplaysFound:
            return "未检测到可用显示器。"
        case .captureFailed(let message):
            return "截屏失败：\(message)"
        }
    }
}

public enum WindowCoordinateHelper {
    /// Converts a CoreGraphics global rect (top-left origin on primary display) into AppKit global coordinates (bottom-left origin).
    public static func cgRectToAppKit(_ cgRect: CGRect, primaryScreenHeight: CGFloat) -> CGRect {
        CGRect(
            x: cgRect.origin.x,
            y: primaryScreenHeight - cgRect.origin.y - cgRect.size.height,
            width: cgRect.size.width,
            height: cgRect.size.height
        )
    }

    public static func filterWindowDictionaries(
        _ rawList: [[String: Any]],
        ownPID: pid_t,
        primaryScreenHeight: CGFloat
    ) -> [WindowInfo] {
        var result: [WindowInfo] = []
        let ignoredOwners: Set<String> = [
            "Window Server",
            "WindowManager",
            "Wallpaper",
            "Spotlight"
        ]

        for entry in rawList {
            if let pid = entry[kCGWindowOwnerPID as String] as? pid_t, pid == ownPID {
                continue
            }
            let alpha = entry[kCGWindowAlpha as String] as? Double ?? 1.0
            if alpha <= 0.01 { continue }

            let layer = entry[kCGWindowLayer as String] as? Int ?? 0
            // Include standard windows (0) and floating panels/sheets (< 24), excluding desktop & status bar layers.
            if layer < 0 || layer >= 24 { continue }

            let owner = entry[kCGWindowOwnerName as String] as? String ?? ""
            if ignoredOwners.contains(owner) { continue }

            guard let boundsDict = entry[kCGWindowBounds as String] as? [String: Any],
                  let cgRect = CGRect(dictionaryRepresentation: boundsDict as CFDictionary) else {
                continue
            }
            if cgRect.width < 20 || cgRect.height < 20 { continue }

            // Dock creates an invisible full-screen window in some macOS versions; skip oversized Dock entries.
            if owner == "Dock" && (cgRect.width > 1200 && cgRect.height > 700) {
                continue
            }

            let windowID = entry[kCGWindowNumber as String] as? CGWindowID ?? 0
            let appKitRect = cgRectToAppKit(cgRect, primaryScreenHeight: primaryScreenHeight)
            result.append(WindowInfo(
                windowID: windowID,
                ownerName: owner,
                layer: layer,
                appKitBounds: appKitRect
            ))
        }
        return result
    }

    /// Returns the topmost window rect (clipped to `screenFrame` and converted to `screenFrame`-local coordinates) containing `localPoint`.
    public static func hitTestLocalWindow(
        atLocalPoint localPoint: CGPoint,
        localWindows: [CGRect]
    ) -> CGRect? {
        for rect in localWindows where rect.contains(localPoint) {
            return rect
        }
        return nil
    }

    public static func localWindows(from globalWindows: [WindowInfo], forScreenFrame screenFrame: CGRect) -> [CGRect] {
        var list: [CGRect] = []
        for win in globalWindows {
            let clipped = win.appKitBounds.intersection(screenFrame)
            guard !clipped.isNull, clipped.width >= 20, clipped.height >= 20 else { continue }
            let local = CGRect(
                x: clipped.origin.x - screenFrame.origin.x,
                y: clipped.origin.y - screenFrame.origin.y,
                width: clipped.width,
                height: clipped.height
            )
            list.append(local)
        }
        return list
    }
}

public final class ScreenCaptureService {
    public init() {}

    public static func hasScreenRecordingPermission() -> Bool {
        CGPreflightScreenCaptureAccess()
    }

    @discardableResult
    public static func requestScreenRecordingPermission() -> Bool {
        CGRequestScreenCaptureAccess()
    }

    public func captureAllScreens() async throws -> [CapturedScreen] {
        if !Self.hasScreenRecordingPermission() {
            Self.requestScreenRecordingPermission()
            throw ScreenCaptureError.permissionDenied
        }

        let screens = NSScreen.screens
        guard !screens.isEmpty else {
            throw ScreenCaptureError.noDisplaysFound
        }

        let primaryHeight = screens.first(where: { $0.frame.origin == .zero })?.frame.height
            ?? screens[0].frame.height

        let ownPID = ProcessInfo.processInfo.processIdentifier
        let rawWindows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        let globalWindows = WindowCoordinateHelper.filterWindowDictionaries(
            rawWindows,
            ownPID: ownPID,
            primaryScreenHeight: primaryHeight
        )

        let shareableContent: SCShareableContent
        do {
            shareableContent = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        } catch {
            throw ScreenCaptureError.captureFailed(error.localizedDescription)
        }

        let ownSCWindows = shareableContent.windows.filter { $0.owningApplication?.processID == ownPID }
        let displayMap = Dictionary(uniqueKeysWithValues: shareableContent.displays.map { ($0.displayID, $0) })

        var captured: [CapturedScreen] = []
        for screen in screens {
            guard let screenNumber = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
                continue
            }
            let displayID = CGDirectDisplayID(screenNumber.uint32Value)
            guard let scDisplay = displayMap[displayID] else { continue }

            let filter = SCContentFilter(display: scDisplay, excludingWindows: ownSCWindows)
            let config = SCStreamConfiguration()
            let scale = max(screen.backingScaleFactor, 1.0)
            config.width = Int(round(screen.frame.width * scale))
            config.height = Int(round(screen.frame.height * scale))
            config.showsCursor = false
            config.capturesAudio = false

            let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
            let localWins = WindowCoordinateHelper.localWindows(from: globalWindows, forScreenFrame: screen.frame)
            captured.append(CapturedScreen(
                screen: screen,
                displayID: displayID,
                image: image,
                localWindows: localWins
            ))
        }

        guard !captured.isEmpty else {
            throw ScreenCaptureError.noDisplaysFound
        }
        return captured
    }
}
