// swift-tools-version: 5.9
// Swift Package Manager support for the Flutter `ble_shield` plugin (darwin shared sources).

import PackageDescription

let package = Package(
  name: "ble_shield",
  platforms: [
    .iOS("13.1"),
    .macOS("10.15"),
  ],
  products: [
    // If the plugin name contains `_`, the library name must use `-`.
    .library(name: "ble-shield", targets: ["ble_shield"]),
  ],
  dependencies: [
    // Flutter injects this local package when SwiftPM integration is enabled.
    .package(name: "FlutterFramework", path: "../FlutterFramework"),
  ],
  targets: [
    .target(
      name: "ble_shield",
      dependencies: [
        .product(name: "FlutterFramework", package: "FlutterFramework"),
      ],
      cSettings: [
        // Expose any public headers (if/when added) under the SPM include directory.
        .headerSearchPath("include/ble_shield")
      ]
    ),
  ]
)

