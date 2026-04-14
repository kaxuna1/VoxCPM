// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "PushToTalkSTT",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/argmaxinc/WhisperKit.git", from: "0.9.0"),
    ],
    targets: [
        .executableTarget(
            name: "PushToTalkSTT",
            dependencies: ["WhisperKit"],
            path: "PushToTalkSTT",
            exclude: ["Resources", "Info.plist", "PushToTalkSTT.entitlements"],
            linkerSettings: [
                .linkedFramework("SwiftUI"),
                .linkedFramework("AppKit"),
                .linkedFramework("AVFoundation"),
                .linkedFramework("ApplicationServices"),
                .linkedFramework("CoreGraphics"),
                .linkedFramework("Accelerate"),
                .linkedFramework("UserNotifications"),
            ]
        ),
    ]
)
