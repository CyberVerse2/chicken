// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "ChickenKit",
    platforms: [.macOS(.v26), .iOS(.v26)],
    products: [
        .library(name: "ChickenKit", targets: ["ChickenKit"]),
    ],
    targets: [
        .target(name: "ChickenKit"),
        .testTarget(name: "ChickenKitTests", dependencies: ["ChickenKit"]),
    ]
)
