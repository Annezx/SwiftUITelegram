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
        ),
        .package(
            url: "https://github.com/airbnb/lottie-spm",
            exact: "4.6.1"
        )
    ],
    targets: [
        .executableTarget(
            name: "SwiftUITelegram",
            dependencies: [
                .product(name: "TDLibKit", package: "TDLibKit"),
                .product(name: "Lottie", package: "lottie-spm")
            ],
            path: "Sources/SwiftUITelegram",
            linkerSettings: [
                .linkedFramework("AVKit"),
                .linkedFramework("AVFoundation"),
                .linkedFramework("CoreMedia"),
                .linkedFramework("CoreVideo"),
                .linkedFramework("QuickLook"),
                .linkedFramework("QuickLookUI"),
                .linkedFramework("VideoToolbox"),
                .linkedFramework("WebKit"),
                .linkedLibrary("compression")
            ]
        )
    ],
    swiftLanguageModes: [.v5]
)
