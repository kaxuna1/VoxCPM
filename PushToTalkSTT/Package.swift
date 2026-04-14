// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "PushToTalkSTT",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/FluidInference/FluidAudio.git", from: "0.1.0"),
    ],
    targets: [
        .executableTarget(
            name: "PushToTalkSTT",
            dependencies: ["FluidAudio"],
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
