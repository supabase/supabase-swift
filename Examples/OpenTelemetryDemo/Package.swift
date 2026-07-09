// swift-tools-version:6.1
import PackageDescription

let package = Package(
  name: "OpenTelemetryDemo",
  platforms: [.macOS(.v13)],
  dependencies: [
    .package(path: "../../", traits: ["OpenTelemetry"]),
    .package(url: "https://github.com/open-telemetry/opentelemetry-swift-core.git", from: "2.5.0"),
  ],
  targets: [
    .executableTarget(
      name: "OpenTelemetryDemo",
      dependencies: [
        .product(name: "Supabase", package: "supabase-swift"),
        .product(name: "OpenTelemetryApi", package: "opentelemetry-swift-core"),
        .product(name: "OpenTelemetrySdk", package: "opentelemetry-swift-core"),
        .product(name: "StdoutExporter", package: "opentelemetry-swift-core"),
      ]
    )
  ]
)
