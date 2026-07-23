// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "DebridMusicKit",
    // SwiftData and the modern observation macros set the floor; both platforms are current here.
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "DebridMusicKit", targets: ["DebridMusicKit"]),
    ],
    targets: [
        .target(name: "DebridMusicKit"),
        .testTarget(name: "DebridMusicKitTests", dependencies: ["DebridMusicKit"]),
    ]
)
