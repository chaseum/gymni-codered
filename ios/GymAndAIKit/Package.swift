// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "GymAndAIKit",
    platforms: [.iOS(.v17), .watchOS(.v10), .macOS(.v14)],
    products: [.library(name: "GymAndAIKit", targets: ["GymAndAIKit"])],
    targets: [
        .target(name: "GymAndAIKit", resources: [.copy("Resources/coaching_policy.json")]),
        .testTarget(name: "GymAndAIKitTests", dependencies: ["GymAndAIKit"]),
    ]
)
