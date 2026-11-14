// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Slate",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "Slate", targets: ["Slate"]),
        .executable(name: "SlateTests", targets: ["SlateTests"])
    ],
    targets: [
        .target(
            name: "SlateCore",
            path: "Sources/SlateCore",
            swiftSettings: [
                .swiftLanguageMode(.v5)
            ],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("Carbon"),
                .linkedFramework("ScreenCaptureKit"),
                .linkedFramework("UniformTypeIdentifiers")
            ]
        ),
        .executableTarget(
            name: "Slate",
            dependencies: ["SlateCore"],
            path: "Sources/Slate",
            swiftSettings: [
                .swiftLanguageMode(.v5)
            ]
        ),
        .executableTarget(
            name: "SlateTests",
            dependencies: ["SlateCore"],
            path: "Tests/SlateTests",
            swiftSettings: [
                .swiftLanguageMode(.v5)
            ]
        )
    ]
)
