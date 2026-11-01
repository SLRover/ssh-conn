// swift-tools-version: 6.4
// The swift-tools-version declares the minimum version of Swift required to build this package.

import Foundation
import PackageDescription

/// Начиная с macOS 26 SDK SwiftUI использует макросы, плагин которых
/// (`libSwiftUIMacros.dylib`) поставляется только с Xcode, но не с
/// Command Line Tools. Если Xcode установлен, подключаем его плагины явно:
/// иначе `swift build` из CLT не сможет собрать GUI-цель.
func swiftUIPluginPath() -> String? {
    var candidates: [String] = []

    if let developerDir = ProcessInfo.processInfo.environment["DEVELOPER_DIR"], !developerDir.isEmpty {
        candidates.append("\(developerDir)/Platforms/MacOSX.platform/Developer/usr/lib/swift/host/plugins")
    }
    candidates.append("/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/usr/lib/swift/host/plugins")

    return candidates.first {
        FileManager.default.fileExists(atPath: "\($0)/libSwiftUIMacros.dylib")
    }
}

let guiSwiftSettings: [SwiftSetting] = swiftUIPluginPath().map {
    [.unsafeFlags(["-plugin-path", $0])]
} ?? []

let package = Package(
    name: "ssh-conn",
    platforms: [.macOS(.v14)],
    targets: [
        .target(
            name: "SSHConnCore",
            path: "Sources/SSHConnCore"
        ),
        .executableTarget(
            name: "ssh-conn",
            dependencies: ["SSHConnCore"],
            path: "Sources/SSHConnCLI"
        ),
        .executableTarget(
            name: "ssh-conn-gui",
            dependencies: ["SSHConnCore"],
            path: "Sources/SSHConnGUI",
            swiftSettings: guiSwiftSettings
        )
    ]
)
