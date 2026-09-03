// swift-tools-version:6.1
// The swift-tools-version declares the minimum version of Swift required to build this package.

import CompilerPluginSupport
import Foundation
import PackageDescription

let package = Package(
  name: "Supabase",
  platforms: [
    .iOS(.v16),
    .macCatalyst(.v16),
    .macOS(.v13),
    .watchOS(.v9),
    .tvOS(.v16),
  ],
  products: [
    .library(name: "Auth", targets: ["Auth"]),
    .library(name: "Functions", targets: ["Functions"]),
    .library(name: "PostgREST", targets: ["PostgREST"]),
    // Opt-in. `Supabase` deliberately does not re-export this, so swift-syntax is compiled
    // only for users who write `import PostgrestMacros`.
    .library(name: "PostgrestMacros", targets: ["PostgrestMacros"]),
    .library(name: "Realtime", targets: ["Realtime"]),
    .library(name: "Storage", targets: ["Storage"]),
    .library(name: "Supabase", targets: ["Supabase"]),
  ],
  traits: [
    // Enables W3C traceparent header propagation using opentelemetry-swift's active span.
    "OpenTelemetry"
  ],
  dependencies: [
    .package(url: "https://github.com/apple/swift-crypto.git", "3.0.0"..<"5.0.0"),
    .package(url: "https://github.com/apple/swift-http-types.git", from: "1.3.0"),
    .package(url: "https://github.com/swiftlang/swift-syntax", "601.0.0"..<"605.0.0"),
    // Pinned below 1.11.0: that version requires swift-tools-version 6.2, above this
    // package's current floor (Xcode 16.4+ / Swift 6.1). Widening this range raises
    // the effective minimum toolchain for every consumer — see SDK-1412.
    .package(url: "https://github.com/apple/swift-log.git", "1.5.0"..<"2.0.0"),
    .package(url: "https://github.com/open-telemetry/opentelemetry-swift-core.git", from: "2.5.0"),
    .package(url: "https://github.com/pointfreeco/swift-clocks", from: "1.0.0"),
    .package(url: "https://github.com/pointfreeco/swift-concurrency-extras", from: "1.1.0"),
    .package(url: "https://github.com/pointfreeco/swift-custom-dump", from: "1.3.2"),
    .package(url: "https://github.com/pointfreeco/swift-macro-testing", from: "0.6.0"),
    .package(url: "https://github.com/pointfreeco/swift-snapshot-testing", from: "1.17.0"),
    .package(url: "https://github.com/pointfreeco/xctest-dynamic-overlay", from: "1.2.2"),
    .package(url: "https://github.com/WeTransfer/Mocker", from: "3.0.0"),
    .package(url: "https://github.com/21-DOT-DEV/swift-secp256k1.git", from: "0.23.2"),
    .package(url: "https://github.com/krzyzanowskim/CryptoSwift.git", from: "1.10.0"),
  ],
  targets: [
    .target(
      name: "Helpers",
      dependencies: [
        .product(name: "ConcurrencyExtras", package: "swift-concurrency-extras"),
        .product(name: "HTTPTypes", package: "swift-http-types"),
        .product(name: "Clocks", package: "swift-clocks"),
        .product(name: "Logging", package: "swift-log"),
        .product(name: "XCTestDynamicOverlay", package: "xctest-dynamic-overlay"),
        .product(name: "IssueReporting", package: "xctest-dynamic-overlay"),
      ]
    ),
    .testTarget(
      name: "HelpersTests",
      dependencies: [
        .product(name: "CustomDump", package: "swift-custom-dump"),
        "Helpers",
      ]
    ),
    .target(
      name: "HTTPRuntime",
      dependencies: [
        .product(name: "HTTPTypes", package: "swift-http-types"),
        .product(name: "HTTPTypesFoundation", package: "swift-http-types"),
      ]
    ),
    .testTarget(
      name: "HTTPRuntimeTests",
      dependencies: [
        "HTTPRuntime",
        .product(name: "HTTPTypes", package: "swift-http-types"),
      ]
    ),
    .target(
      name: "HTTPRuntimeTestHelpers",
      dependencies: [
        "HTTPRuntime",
        .product(name: "HTTPTypes", package: "swift-http-types"),
        .product(name: "HTTPTypesFoundation", package: "swift-http-types"),
        .product(name: "InlineSnapshotTesting", package: "swift-snapshot-testing"),
      ]
    ),
    .testTarget(
      name: "HTTPRuntimeTestHelpersTests",
      dependencies: [
        "HTTPRuntime",
        "HTTPRuntimeTestHelpers",
        .product(name: "HTTPTypes", package: "swift-http-types"),
        .product(name: "HTTPTypesFoundation", package: "swift-http-types"),
      ]
    ),
    .target(
      name: "Auth",
      dependencies: [
        .product(name: "ConcurrencyExtras", package: "swift-concurrency-extras"),
        .product(name: "Crypto", package: "swift-crypto"),
        .product(name: "HTTPTypes", package: "swift-http-types"),
        .product(name: "IssueReporting", package: "xctest-dynamic-overlay"),
        .product(name: "Logging", package: "swift-log"),
        "Helpers",
      ]
    ),
    .testTarget(
      name: "AuthTests",
      dependencies: [
        .product(name: "CustomDump", package: "swift-custom-dump"),
        .product(name: "InlineSnapshotTesting", package: "swift-snapshot-testing"),
        .product(name: "SnapshotTesting", package: "swift-snapshot-testing"),
        .product(name: "XCTestDynamicOverlay", package: "xctest-dynamic-overlay"),
        "Auth",
        "Helpers",
        "Mocker",
        "TestHelpers",
      ],
      exclude: [
        "__Snapshots__"
      ],
      resources: [.process("Resources")]
    ),
    .target(
      name: "Functions",
      dependencies: [
        .product(name: "ConcurrencyExtras", package: "swift-concurrency-extras"),
        .product(name: "HTTPTypes", package: "swift-http-types"),
        .product(name: "Logging", package: "swift-log"),
        "Helpers",
      ]
    ),
    .testTarget(
      name: "FunctionsTests",
      dependencies: [
        .product(name: "HTTPTypes", package: "swift-http-types"),
        .product(name: "SnapshotTesting", package: "swift-snapshot-testing"),
        "Functions",
        "Mocker",
        "TestHelpers",
      ],
      exclude: [
        "__Snapshots__"
      ]
    ),
    .testTarget(
      name: "IntegrationTests",
      dependencies: [
        .product(name: "CustomDump", package: "swift-custom-dump"),
        .product(name: "InlineSnapshotTesting", package: "swift-snapshot-testing"),
        .product(name: "XCTestDynamicOverlay", package: "xctest-dynamic-overlay"),
        .product(name: "P256K", package: "swift-secp256k1"),
        .product(name: "CryptoSwift", package: "CryptoSwift"),
        "Helpers",
        "Supabase",
        "TestHelpers",
      ],
      resources: [
        .process("Fixtures"),
        .process("supabase"),
      ]
    ),
    .target(
      name: "PostgREST",
      dependencies: [
        .product(name: "ConcurrencyExtras", package: "swift-concurrency-extras"),
        .product(name: "HTTPTypes", package: "swift-http-types"),
        .product(name: "Logging", package: "swift-log"),
        "Helpers",
      ],
      exclude: [
        "Legacy/README.md"
      ]
    ),
    .testTarget(
      name: "PostgRESTTests",
      dependencies: [
        .product(name: "SnapshotTesting", package: "swift-snapshot-testing"),
        "Helpers",
        "Mocker",
        "PostgREST",
        "TestHelpers",
      ],
      exclude: [
        "__Snapshots__"
      ]
    ),
    .macro(
      name: "PostgrestMacrosPlugin",
      dependencies: [
        .product(name: "SwiftCompilerPlugin", package: "swift-syntax"),
        .product(name: "SwiftDiagnostics", package: "swift-syntax"),
        .product(name: "SwiftSyntaxMacros", package: "swift-syntax"),
      ]
    ),
    .target(
      name: "PostgrestMacros",
      dependencies: [
        "PostgREST",
        "PostgrestMacrosPlugin",
      ]
    ),
    .testTarget(
      name: "PostgrestMacrosTests",
      dependencies: [
        .product(name: "MacroTesting", package: "swift-macro-testing"),
        .product(name: "SwiftSyntaxBuilder", package: "swift-syntax"),
        "PostgrestMacros",
        "PostgrestMacrosPlugin",
      ]
    ),
    .target(
      name: "Realtime",
      dependencies: [
        .product(name: "ConcurrencyExtras", package: "swift-concurrency-extras"),
        .product(name: "HTTPTypes", package: "swift-http-types"),
        .product(name: "IssueReporting", package: "xctest-dynamic-overlay"),
        .product(name: "Logging", package: "swift-log"),
        "Helpers",
      ]
    ),
    .testTarget(
      name: "RealtimeTests",
      dependencies: [
        .product(name: "CustomDump", package: "swift-custom-dump"),
        .product(name: "InlineSnapshotTesting", package: "swift-snapshot-testing"),
        .product(name: "XCTestDynamicOverlay", package: "xctest-dynamic-overlay"),
        "Realtime",
        "TestHelpers",
      ]
    ),
    .target(
      name: "Storage",
      dependencies: [
        .product(name: "ConcurrencyExtras", package: "swift-concurrency-extras"),
        .product(name: "HTTPTypes", package: "swift-http-types"),
        .product(name: "Logging", package: "swift-log"),
        "Helpers",
      ]
    ),
    .testTarget(
      name: "StorageTests",
      dependencies: [
        .product(name: "InlineSnapshotTesting", package: "swift-snapshot-testing"),
        .product(name: "XCTestDynamicOverlay", package: "xctest-dynamic-overlay"),
        "Mocker",
        "TestHelpers",
        "Storage",
      ],
      resources: [
        .copy("sadcat.jpg"),
        .process("Fixtures"),
      ]
    ),
    .target(
      name: "Supabase",
      dependencies: [
        .product(name: "ConcurrencyExtras", package: "swift-concurrency-extras"),
        .product(name: "HTTPTypes", package: "swift-http-types"),
        .product(name: "IssueReporting", package: "xctest-dynamic-overlay"),
        .product(name: "Logging", package: "swift-log"),
        .product(
          name: "OpenTelemetryApi", package: "opentelemetry-swift-core",
          condition: .when(traits: ["OpenTelemetry"])
        ),
        "Auth",
        "Functions",
        "PostgREST",
        "Realtime",
        "Storage",
      ]
    ),
    .testTarget(
      name: "SupabaseTests",
      dependencies: [
        .product(name: "ConcurrencyExtras", package: "swift-concurrency-extras"),
        .product(name: "CustomDump", package: "swift-custom-dump"),
        .product(name: "HTTPTypes", package: "swift-http-types"),
        .product(name: "InlineSnapshotTesting", package: "swift-snapshot-testing"),
        .product(
          name: "OpenTelemetryApi", package: "opentelemetry-swift-core",
          condition: .when(traits: ["OpenTelemetry"])
        ),
        .product(
          name: "OpenTelemetrySdk", package: "opentelemetry-swift-core",
          condition: .when(traits: ["OpenTelemetry"])
        ),
        "Supabase",
      ]
    ),
    .target(
      name: "TestHelpers",
      dependencies: [
        .product(name: "ConcurrencyExtras", package: "swift-concurrency-extras"),
        .product(name: "InlineSnapshotTesting", package: "swift-snapshot-testing"),
        .product(name: "XCTestDynamicOverlay", package: "xctest-dynamic-overlay"),
        "Auth",
        "Helpers",
        "Mocker",
      ]
    ),
  ]
)

for target in package.targets {
  var swiftSettings: [SwiftSetting] = [
    .enableUpcomingFeature("ExistentialAny"),
    .enableUpcomingFeature("ImmutableWeakCaptures"),
    .enableUpcomingFeature("InferIsolatedConformances"),
  ]

  // The compiler-plugin target must declare its macro types `public` to satisfy SwiftSyntax's
  // `CompilerPlugin` protocol, and `InternalImportsByDefault` rejects a public conformance to a
  // protocol from an internally-imported module. Plugins run at build time and ship no
  // distributable API, so the two import-visibility features gain nothing there.
  if target.name != "PostgrestMacrosPlugin" {
    swiftSettings.append(.enableUpcomingFeature("InternalImportsByDefault"))
    swiftSettings.append(.enableUpcomingFeature("MemberImportVisibility"))
  }

  target.swiftSettings = swiftSettings
}
