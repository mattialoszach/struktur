// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Struktur",
    platforms: [.macOS(.v15)],
    products: [
        .executable(name: "Struktur", targets: ["Struktur"])
    ],
    dependencies: [
        .package(url: "https://github.com/mgriebling/SwiftMath.git", exact: "1.7.3")
    ],
    targets: [
        .executableTarget(
            name: "Struktur",
            dependencies: [.product(name: "SwiftMath", package: "SwiftMath")],
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
