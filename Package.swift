// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SwiftUITelegram",
    defaultLocalization: "en",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .executable(
            name: "SwiftUITelegram",
            targets: ["SwiftUITelegram"]
        )
    ],
    dependencies: [
        .package(
            url: "https://github.com/Swiftgram/TDLibKit",
            exact: "1.5.2-tdlib-1.8.70-fe61d641"
        )
    ],
    targets: [
        .executableTarget(
            name: "SwiftUITelegram",
            dependencies: [
                .product(name: "TDLibKit", package: "TDLibKit")
            ],
            path: "Sources/SwiftUITelegram",
            linkerSettings: [
                .linkedFramework("AVKit"),
                .linkedFramework("AVFoundation"),
                .linkedFramework("QuickLook"),
                .linkedFramework("QuickLookUI")
            ]
        )
    ],
    swiftLanguageModes: [.v5]
)
