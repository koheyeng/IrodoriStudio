// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "IrodoriStudio",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "IrodoriKit", targets: ["IrodoriKit"]),
        .executable(name: "IrodoriStudio", targets: ["IrodoriStudio"]),
    ],
    targets: [
        // 画面に依存しない部分（データの形・キャプション組み立て・絵文字・音声合成のプロトコル）
        .target(
            name: "IrodoriKit",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .executableTarget(
            name: "IrodoriStudio",
            dependencies: ["IrodoriKit"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "IrodoriKitTests",
            dependencies: ["IrodoriKit"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "IrodoriStudioTests",
            dependencies: ["IrodoriStudio"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
