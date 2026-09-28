// swift-tools-version: 6.0
// Pure-logic tests for the app, runnable without Xcode: `swift test --package-path Tests`.
// Sources/JarvisCore holds symlinks to the app files that don't need the UI or KeyboardShortcuts.
import PackageDescription

let package = Package(
    name: "JarvisTests",
    platforms: [.macOS(.v15)],
    targets: [
        .target(name: "JarvisCore", path: "Sources/JarvisCore"),
        .testTarget(name: "JarvisTests", dependencies: ["JarvisCore"], path: "JarvisTests"),
    ]
)
