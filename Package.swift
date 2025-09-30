// swift-tools-version: 6.1
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

internal let package = Package(
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
        .package(url: "https://github.com/vapor/console-kit.git", from: "4.1.5"),
        .package(url: "https://github.com/Alamofire/Alamofire.git", .upToNextMajor(from: "5.10.0")),
        .package(url: "https://github.com/getautomaapp/swift-any-codable/", from: "1.0.0")
    ],
    targets: [
        .executableTarget(
            name: "AutomaCLI",
            dependencies: [
                .product(name: "ConsoleKit", package: "console-kit"),
                .product(name: "Alamofire", package: "Alamofire"),
                .product(name: "AnyCodable", package: "swift-any-codable")
            ],
            linkerSettings: [
                .linkedLibrary("curl")
            ]
        ),
    ]
)
