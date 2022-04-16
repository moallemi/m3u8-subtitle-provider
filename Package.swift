// swift-tools-version:5.5
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
  name: "m3u8-subtitle-provider",
  platforms: [.iOS(.v15), .macOS(.v12), .tvOS(.v15)],
  products: [
    .library(
      name: "SubtitleProvider",
      targets: ["SubtitleProvider"]
    ),
  ],
  dependencies: [
    .package(url: "https://github.com/apple/swift-nio.git", from: "2.38.0"),
  ],
  targets: [
    .target(
      name: "SubtitleProvider",
      dependencies: [
        .product(name: "NIOHTTP1", package: "swift-nio"),
      ]
    ),
  ]
)
