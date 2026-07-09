//
//  main.swift
//

import ArgumentParser
import Foundation
import OpenAPICodegenCore
import OpenAPIKit30

struct OpenAPICodegen: ParsableCommand {
  static let configuration = CommandConfiguration(commandName: "openapi-codegen")

  @Option(help: "Path to the OpenAPI spec file.")
  var spec: String

  @Option(help: "Directory to write the generated Swift files into.")
  var output: String

  @Option(help: "Name of the generated module (used to derive the client type name).")
  var module: String

  func run() throws {
    let specURL = URL(fileURLWithPath: spec)
    let outputURL = URL(fileURLWithPath: output, isDirectory: true)

    let data = try Data(contentsOf: specURL)
    let document = try JSONDecoder().decode(OpenAPI.Document.self, from: data)
    let irDocument = try OpenAPIParsing.parseDocument(document)

    try FileManager.default.createDirectory(at: outputURL, withIntermediateDirectories: true)

    let models = SwiftEmitter.emitModels(irDocument)
    try models.write(
      to: outputURL.appendingPathComponent("Models.swift"), atomically: true, encoding: .utf8)

    let clientName = "\(module)Client"
    let client = SwiftEmitter.emitClient(irDocument, clientName: clientName)
    try client.write(
      to: outputURL.appendingPathComponent("\(clientName).swift"), atomically: true,
      encoding: .utf8)

    print(
      "Generated \(irDocument.schemas.count) schemas and \(irDocument.operations.count) operations into \(outputURL.path)"
    )
  }
}

OpenAPICodegen.main()
