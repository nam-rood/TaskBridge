// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "LarkFlow",
    platforms: [
        .macOS(.v13) // 使用 MenuBarExtra 需要 macOS 13.0 及以上版本
    ],
    dependencies: [
        // 引入 GRDB 作为 SQLite 的封装库，它非常轻量且 Swift 友好
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "6.24.0")
    ],
    targets: [
        // Targets are the basic building blocks of a package, defining a module or a test suite.
        // Targets can depend on other targets in this package and products from dependencies.
        .executableTarget(
            name: "LarkFlow",
            dependencies: [
                .product(name: "GRDB", package: "GRDB.swift")
            ]
        ),
        .testTarget(
            name: "LarkFlowTests",
            dependencies: ["LarkFlow"]
        ),
    ]
)