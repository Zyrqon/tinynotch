// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Notchly",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "Notchly",
            path: "Sources/Notchly",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("SwiftUI"),
                .linkedFramework("CoreAudio"),
                .linkedFramework("AudioToolbox"),
                .linkedFramework("IOKit"),
                .linkedFramework("QuickLookThumbnailing"),
                .linkedFramework("ServiceManagement"),
                .linkedFramework("IOBluetooth"),
                .linkedFramework("CoreLocation"),
                .linkedFramework("LocalAuthentication"),
                .linkedFramework("Network"),
                .linkedLibrary("sqlite3"),
            ]
        )
    ]
)
