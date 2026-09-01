// swift-tools-version:5.7
import PackageDescription

let package = Package(
    name: "EmbedIOSSDK",
    platforms: [
        .iOS(.v16)
    ],
    products: [
        .library(
            name: "EmbedIOSSDK",
            targets: ["EmbedIOSSDK"]
        )
    ],
    targets: [
        .target(
            name: "EmbedIOSSDK",
            path: "Sources/EmbedIOSSDK"
        )
    ]
)
