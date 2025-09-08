// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ics2cal",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "ics2cal", targets: ["ICS2Cal"]) 
    ],
    dependencies: [],
    targets: [
        .executableTarget(
            name: "ICS2Cal",
            path: "Sources/ICS2Cal"
        ),
        .testTarget(
            name: "ICS2CalTests",
            path: "Tests/ICS2CalTests",
            dependencies: ["ICS2Cal"],
            resources: [.process("Fixtures")]
        )
    ]
)

