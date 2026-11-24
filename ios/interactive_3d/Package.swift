// swift-tools-version: 5.9
// Swift Package Manager manifest for the interactive_3d Flutter plugin.
// Coexists with interactive_3d.podspec; both build paths reference the same
// Sources/interactive_3d directory.

import PackageDescription

let package = Package(
  name: "interactive_3d",
  platforms: [
    .iOS("12.0")
  ],
  products: [
    .library(name: "interactive-3d", targets: ["interactive_3d"])
  ],
  dependencies: [
    .package(name: "FlutterFramework", path: "../FlutterFramework"),
    .package(url: "https://github.com/magicien/GLTFSceneKit.git", "0.3.0"..<"0.5.0")
  ],
  targets: [
    .target(
      name: "interactive_3d",
      dependencies: [
        .product(name: "FlutterFramework", package: "FlutterFramework"),
        "GLTFSceneKit"
      ]
    )
  ]
)
