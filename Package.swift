// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Struktur",
    platforms: [.macOS(.v15)],
    products: [
        .executable(name: "Struktur", targets: ["Struktur"])
    ],
    targets: [
        .executableTarget(
            name: "Struktur",
            resources: [.process("Resources")],
            swiftSettings: [
                .enableUpcomingFeature("StrictConcurrency")
            ]
        ),
        .testTarget(
            name: "StrukturTests",
            dependencies: ["Struktur"]
        )
    ]
)
