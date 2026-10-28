// swift-tools-version:6.4

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
    .visionOS(.v1),
  ],
  products: [
    .library(name: "Auth", targets: ["Auth"]),
    .library(name: "Functions", targets: ["Functions"]),
    .library(name: "PostgREST", targets: ["PostgREST"]),
    .library(name: "PostgrestMacros", targets: ["PostgrestMacros"]),
    .library(name: "Realtime", targets: ["Realtime"]),
    .library(name: "Storage", targets: ["Storage"]),
    .library(name: "Supabase", targets: ["Supabase"]),
  ],
  traits: [
    "OpenTelemetry"
  ],
  dependencies: [
    .package(url: "https://github.com/apple/swift-crypto.git", "3.0.0"..<"6.0.0"),
    .package(url: "https://github.com/apple/swift-http-types.git", from: "1.3.0"),
    .package(url: "https://github.com/swiftlang/swift-syntax", "601.0.0"..<"605.0.0"),
    .package(url: "https://github.com/apple/swift-log.git", "1.5.0"..<"2.0.0"),
    .package(url: "https://github.com/open-telemetry/opentelemetry-swift-core.git", from: "2.5.0"),
    .package(url: "https://github.com/pointfreeco/swift-clocks", from: "1.0.0"),
    .package(url: "https://github.com/pointfreeco/swift-concurrency-extras", from: "1.1.0"),
    .package(url: "https://github.com/pointfreeco/swift-custom-dump", from: "1.3.2"),
    .package(url: "https://github.com/pointfreeco/swift-macro-testing", from: "0.6.0"),
    .package(url: "https://github.com/pointfreeco/swift-snapshot-testing", from: "1.17.0"),
    .package(url: "https://github.com/pointfreeco/swift-issue-reporting", from: "2.1.0"),
    .package(url: "https://github.com/WeTransfer/Mocker", from: "3.0.0"),
    .package(url: "https://github.com/21-DOT-DEV/swift-secp256k1.git", from: "0.23.2"),
  ],
  targets: [
    .target(
      name: "Helpers",
      dependencies: [
        .product(name: "ConcurrencyExtras", package: "swift-concurrency-extras"),
        .product(name: "HTTPTypes", package: "swift-http-types"),
        .product(name: "HTTPTypesFoundation", package: "swift-http-types"),
        .product(name: "Logging", package: "swift-log"),
        .product(name: "IssueReporting", package: "swift-issue-reporting"),
      ],
      resources: [.copy("PrivacyInfo.xcprivacy")]
    ),
    .testTarget(
      name: "HelpersTests",
      dependencies: [
        .product(name: "Clocks", package: "swift-clocks"),
        .product(name: "CustomDump", package: "swift-custom-dump"),
        .product(name: "HTTPTypes", package: "swift-http-types"),
        "Helpers",
        "Mocker",
        "TestHelpers",
      ]
    ),
    .target(
      name: "Auth",
      dependencies: [
        .product(name: "ConcurrencyExtras", package: "swift-concurrency-extras"),
        .product(name: "Crypto", package: "swift-crypto"),
        .product(name: "HTTPTypes", package: "swift-http-types"),
        .product(name: "IssueReporting", package: "swift-issue-reporting"),
        .product(name: "Logging", package: "swift-log"),
        "Helpers",
      ]
    ),
    .testTarget(
      name: "AuthTests",
      dependencies: [
        .product(name: "Clocks", package: "swift-clocks"),
        .product(name: "CustomDump", package: "swift-custom-dump"),
        .product(name: "InlineSnapshotTesting", package: "swift-snapshot-testing"),
        .product(name: "SnapshotTesting", package: "swift-snapshot-testing"),
        .product(name: "IssueReporting", package: "swift-issue-reporting"),
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
        .product(name: "HTTPTypes", package: "swift-http-types"),
        .product(name: "IssueReporting", package: "swift-issue-reporting"),
        .product(name: "Logging", package: "swift-log"),
        "Helpers",
      ]
    ),
    .testTarget(
      name: "FunctionsTests",
      dependencies: [
        .product(name: "HTTPTypes", package: "swift-http-types"),
        .product(name: "HTTPTypesFoundation", package: "swift-http-types"),
        .product(name: "InlineSnapshotTesting", package: "swift-snapshot-testing"),
        .product(name: "IssueReporting", package: "swift-issue-reporting"),
        "Functions",
        "Mocker",
        "TestHelpers",
      ]
    ),
    .testTarget(
      name: "IntegrationTests",
      dependencies: [
        .product(name: "Clocks", package: "swift-clocks"),
        .product(name: "CustomDump", package: "swift-custom-dump"),
        .product(name: "InlineSnapshotTesting", package: "swift-snapshot-testing"),
        .product(name: "IssueReporting", package: "swift-issue-reporting"),
        .product(name: "P256K", package: "swift-secp256k1"),
        "Helpers",
        "PostgrestMacros",
        "Supabase",
        "TestHelpers",
      ],
      // The edge functions are served by `supabase start`, not bundled; `.process` flattens
      // the tree, so their `index.ts` files would collide.
      exclude: ["supabase/functions"],
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
        "Untyped/README.md"
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
    .testTarget(
      name: "SupabaseTypegenOutputTests",
      dependencies: [
        .product(name: "HTTPTypes", package: "swift-http-types"),
        "PostgrestMacros",
        "TestHelpers",
      ]
    ),
    .testTarget(
      name: "SupabaseTypegenPostgrestTypegenOutputTests",
      dependencies: [
        .product(name: "HTTPTypes", package: "swift-http-types"),
        "PostgrestMacros",
        "TestHelpers",
      ]
    ),
    .testTarget(
      name: "SupabaseTypegenHostileOutputTests",
      dependencies: ["PostgrestMacros"]
    ),
    .target(
      name: "Realtime",
      dependencies: [
        .product(name: "ConcurrencyExtras", package: "swift-concurrency-extras"),
        .product(name: "HTTPTypes", package: "swift-http-types"),
        .product(name: "IssueReporting", package: "swift-issue-reporting"),
        .product(name: "Logging", package: "swift-log"),
        "Helpers",
      ]
    ),
    .testTarget(
      name: "RealtimeTests",
      dependencies: [
        .product(name: "Clocks", package: "swift-clocks"),
        .product(name: "CustomDump", package: "swift-custom-dump"),
        .product(name: "InlineSnapshotTesting", package: "swift-snapshot-testing"),
        .product(name: "IssueReporting", package: "swift-issue-reporting"),
        "Helpers",
        "Realtime",
        "TestHelpers",
      ]
    ),
    .target(
      name: "Storage",
      dependencies: [
        .product(name: "ConcurrencyExtras", package: "swift-concurrency-extras"),
        .product(name: "Crypto", package: "swift-crypto"),
        .product(name: "HTTPTypes", package: "swift-http-types"),
        .product(name: "IssueReporting", package: "swift-issue-reporting"),
        .product(name: "Logging", package: "swift-log"),
        "Helpers",
      ]
    ),
    .testTarget(
      name: "StorageTests",
      dependencies: [
        .product(name: "Clocks", package: "swift-clocks"),
        .product(name: "InlineSnapshotTesting", package: "swift-snapshot-testing"),
        .product(name: "IssueReporting", package: "swift-issue-reporting"),
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
        .product(name: "IssueReporting", package: "swift-issue-reporting"),
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
        .product(name: "Clocks", package: "swift-clocks"),
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
        "TestHelpers",
      ]
    ),
    .testTarget(
      name: "DefaultIsolationTests",
      dependencies: ["Supabase"]
    ),
    .target(
      name: "TestHelpers",
      dependencies: [
        .product(name: "Clocks", package: "swift-clocks"),
        .product(name: "ConcurrencyExtras", package: "swift-concurrency-extras"),
        .product(name: "InlineSnapshotTesting", package: "swift-snapshot-testing"),
        .product(name: "IssueReporting", package: "swift-issue-reporting"),
        .product(name: "Logging", package: "swift-log"),
        "Auth",
        "Helpers",
        "Mocker",
        "Realtime",
      ]
    ),
  ]
)

for target in package.targets {
  var swiftSettings: [SwiftSetting] = [
    .enableUpcomingFeature("ExistentialAny"),
    .enableUpcomingFeature("ImmutableWeakCaptures"),
    .enableUpcomingFeature("InferIsolatedConformances"),
    .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
  ]

  if target.name != "PostgrestMacrosPlugin" {
    swiftSettings.append(.enableUpcomingFeature("InternalImportsByDefault"))
    swiftSettings.append(.enableUpcomingFeature("MemberImportVisibility"))
  }

  if target.name == "DefaultIsolationTests" {
    swiftSettings.append(.defaultIsolation(MainActor.self))
  }

  // Apple platforms only: on Linux, Foundation is not built with library evolution, so the
  // flag fails.
  if [
    "SupabaseTypegenOutputTests",
    "SupabaseTypegenPostgrestTypegenOutputTests",
    "SupabaseTypegenHostileOutputTests",
  ].contains(target.name) {
    swiftSettings.append(
      .unsafeFlags(
        ["-enable-library-evolution"],
        .when(platforms: [.macOS, .iOS, .tvOS, .watchOS, .visionOS, .macCatalyst])
      )
    )
  }

  target.swiftSettings = swiftSettings
}
