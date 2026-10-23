// swift-tools-version: 6.4
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "ssh-conn",
    targets: [
        .executableTarget(
            name: "ssh_conn",
            path: "Sources"
        )
    ]
)
