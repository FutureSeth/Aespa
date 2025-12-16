// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "Aespa",
    platforms: [.iOS("17.0")],
    products: [
        .library(
            name: "Aespa",
            targets: ["Aespa"]),
    ],
    dependencies: [],
    targets: [
        .target(
            name: "Aespa",
            dependencies: [])
    ]
)
