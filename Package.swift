// swift-tools-version: 6.1
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "AutomaCLI",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .executable(
            name: "automa",
            targets: ["AutomaCLI"]
        )
    ],
    dependencies: [
        .package(url: "https://github.com/vapor/console-kit.git", from: "4.1.5")
    ],
    targets: [
        .executableTarget(
            name: "AutomaCLI",
            dependencies: [
                .product(name: "ConsoleKit", package: "console-kit")
            ]
        ),
    ]
)
