// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "PowerClue",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "PowerClue", targets: ["PowerClue"])],
    targets: [
        .executableTarget(
            name: "PowerClue",
            linkerSettings: [.linkedFramework("IOKit")]
        )
    ]
)
