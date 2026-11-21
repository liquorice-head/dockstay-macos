// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "DockStay",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "DockStay", targets: ["DockStay"])],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.10.1")
    ],
    targets: [
        .target(name: "DockStayCore"),
        .executableTarget(
            name: "DockStay",
            dependencies: ["DockStayCore", .product(name: "Sparkle", package: "Sparkle")],
            linkerSettings: [.unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])]
        ),
        .testTarget(name: "DockStayCoreTests", dependencies: ["DockStayCore"])
    ]
)
