// swift-tools-version: 6.0
import PackageDescription

let package = Package(
  name: "_Realtime",
  platforms: [
    .iOS(.v17),
    .macOS(.v14),
    .tvOS(.v17),
    .watchOS(.v10),
    .visionOS(.v1),
  ],
  products: [
    .library(name: "_Realtime", targets: ["_Realtime"]),
  ],
  dependencies: [
    .package(url: "https://github.com/pointfreeco/swift-clocks", from: "1.0.0"),
    .package(url: "https://github.com/pointfreeco/swift-concurrency-extras", from: "1.1.0"),
    .package(url: "https://github.com/pointfreeco/xctest-dynamic-overlay", from: "1.2.2"),
    .package(url: "https://github.com/pointfreeco/swift-custom-dump", from: "1.3.2"),
    .package(url: "https://github.com/pointfreeco/swift-snapshot-testing", from: "1.17.0"),
  ],
  targets: [
    .target(
      name: "_Realtime",
      dependencies: [
        .product(name: "Clocks", package: "swift-clocks"),
        .product(name: "ConcurrencyExtras", package: "swift-concurrency-extras"),
        .product(name: "IssueReporting", package: "xctest-dynamic-overlay"),
      ],
      swiftSettings: [
        .swiftLanguageMode(.v6),
        .enableUpcomingFeature("ExistentialAny"),
      ]
    ),
    .testTarget(
      name: "_RealtimeTests",
      dependencies: [
        .product(name: "Clocks", package: "swift-clocks"),
        .product(name: "CustomDump", package: "swift-custom-dump"),
        .product(name: "InlineSnapshotTesting", package: "swift-snapshot-testing"),
        .product(name: "ConcurrencyExtras", package: "swift-concurrency-extras"),
        "_Realtime",
      ]
    ),
  ]
)
