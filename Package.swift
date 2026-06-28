// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "FriendlyLangTutor",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(
            name: "FriendlyLangTutor",
            targets: ["FriendlyLangTutor"]
        )
    ],
    targets: [
        .executableTarget(
            name: "FriendlyLangTutor",
            path: "app",
            exclude: ["Info.plist"],
            resources: [.copy("seeds")]
        )
    ]
)
