// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "GordonKirschAPI",
    platforms: [.iOS(.v16)],
    products: [
        // Products define the executables and libraries a package produces, making them visible to other packages.
        .library(
            name: "GordonKirschAPI",
            targets: ["GordonKirschAPI"]),
    ],
    dependencies: [
        .package(url: "https://github.com/fantasia-y/GordonKirschUtils.git", .upToNextMajor(from: "1.0.0")),
        .package(url: "https://github.com/auth0/JWTDecode.swift", .upToNextMajor(from: "3.1.0")),
        .package(url: "https://github.com/evgenyneu/keychain-swift.git", .upToNextMajor(from: "20.0.0")),
    ],
    targets: [
        // Targets are the basic building blocks of a package, defining a module or a test suite.
        // Targets can depend on other targets in this package and products from dependencies.
        .target(
            name: "GordonKirschAPI",
            dependencies: [
                .product(name: "GordonKirschUtils", package: "GordonKirschUtils"),
                .product(name: "JWTDecode", package: "JWTDecode.swift"),
                .product(name: "KeychainSwift", package: "keychain-swift")
            ]),
    ]
)
