// swift-tools-version:5.1
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "HTMLArchiving",
    platforms: [
             .macOS(.v10_13),
             .iOS(.v12),
             .watchOS(.v5)
        ],
    products: [
        // Products define the executables and libraries produced by a package, and make them visible to other packages.
		.library(
			name: "HTMLArchiving",
			targets: ["HTMLArchiving", "ParseHTML"]),
    ],
    dependencies: [
        .package(url: "https://github.com/bengottlieb/Suite.git", from: "0.9.87"),
//        .package(url: "https://bengottlieb@github.com/standalone/gulliver", from: "1.0.5"),
        .package(url: "https://bengottlieb@github.com/bengottlieb/plug", from: "1.0.1"),
        .package(url: "https://bengottlieb@github.com/bengottlieb/crossplatformkit", from: "1.0.2"),
    ],
    targets: [
        // Targets are the basic building blocks of a package. A target can define a module or a test suite.
        // Targets can depend on other targets in this package, and on products in packages which this package depends on.
		.target(
			name: "HTMLArchiving",
			dependencies: ["ParseHTML", "Plug", "CrossPlatformKit", "Studio"]),
		.target(
			name: "ParseHTML",
			dependencies: []),
    ]
)
