import Foundation

public final class LaunchAtLoginManager {
    public static let label = "com.slate.screenshot"
    public static let defaultExecutablePath = "/Applications/Slate.app/Contents/MacOS/Slate"

    public let plistURL: URL

    public init(plistURL: URL? = nil) {
        if let plistURL = plistURL {
            self.plistURL = plistURL
        } else {
            let library = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first
                ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library")
            self.plistURL = library
                .appendingPathComponent("LaunchAgents", isDirectory: true)
                .appendingPathComponent("\(Self.label).plist")
        }
    }

    public var isEnabled: Bool {
        guard let data = try? Data(contentsOf: plistURL),
              let dict = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else {
            return false
        }
        return (dict["RunAtLoad"] as? Bool) == true
    }

    public func setEnabled(_ enabled: Bool, executablePath: String? = nil) throws {
        let fm = FileManager.default
        if enabled {
            let dir = plistURL.deletingLastPathComponent()
            if !fm.fileExists(atPath: dir.path) {
                try fm.createDirectory(at: dir, withIntermediateDirectories: true)
            }
            let exec = executablePath ?? resolvedExecutablePath()
            let plist: [String: Any] = [
                "Label": Self.label,
                "ProgramArguments": [exec],
                "RunAtLoad": true,
                "KeepAlive": false,
                "LimitLoadToSessionType": "Aqua",
                "ProcessType": "Interactive"
            ]
            let data = try PropertyListSerialization.data(
                fromPropertyList: plist,
                format: .xml,
                options: 0
            )
            try data.write(to: plistURL, options: .atomic)
        } else {
            if fm.fileExists(atPath: plistURL.path) {
                try fm.removeItem(at: plistURL)
            }
        }
    }

    private func resolvedExecutablePath() -> String {
        if let path = Bundle.main.executablePath, path.hasSuffix(".app/Contents/MacOS/Slate") {
            return path
        }
        return Self.defaultExecutablePath
    }
}
