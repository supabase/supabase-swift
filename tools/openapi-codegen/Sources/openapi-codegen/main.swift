//
//  main.swift
//

import ArgumentParser
import Foundation
import OpenAPICodegenCore
import OpenAPIKit

struct OpenAPICodegen: ParsableCommand {
  static let configuration = CommandConfiguration(commandName: "openapi-codegen")

  @Option(help: "Path to the OpenAPI spec file.")
  var spec: String

  @Option(help: "Directory to write the generated Swift files into.")
  var output: String

  @Option(help: "Name of the enum namespace generated declarations are nested under.")
  var namespace: String

  @Option(
    help:
      "Access level for generated declarations: public, package, or internal (default: internal).")
  var accessLevel: String = "internal"

  func run() throws {
    guard let accessLevel = AccessLevel(rawValue: accessLevel) else {
      throw ValidationError(
        "--access-level must be one of: \(AccessLevel.allCases.map(\.rawValue).joined(separator: ", "))"
      )
    }

    let specURL = URL(fileURLWithPath: spec)
    let outputURL = URL(fileURLWithPath: output, isDirectory: true)

    let data = try Data(contentsOf: specURL)
    let normalizedData = try SpecNormalization.dropValidationOnlyUnions(data)
    let document = try JSONDecoder().decode(OpenAPI.Document.self, from: normalizedData)
    let irDocument = try OpenAPIParsing.parseDocument(document)

    try FileManager.default.createDirectory(at: outputURL, withIntermediateDirectories: true)

    let models = SwiftEmitter.emitModels(
      irDocument, namespace: namespace, accessLevel: accessLevel)
    try models.write(
      to: outputURL.appendingPathComponent("Models.swift"), atomically: true, encoding: .utf8)

    let client = SwiftEmitter.emitClient(
      irDocument, namespace: namespace, accessLevel: accessLevel)
    try client.write(
      to: outputURL.appendingPathComponent("Client.swift"), atomically: true,
      encoding: .utf8)

    print(
      "Generated \(irDocument.schemas.count) schemas and \(irDocument.operations.count) operations into \(outputURL.path)"
    )
  }
}

OpenAPICodegen.main()
