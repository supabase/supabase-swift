//
//  main.swift
//

import Foundation
import OpenAPICodegenCore
import OpenAPIKit30

struct CLIError: Error, CustomStringConvertible {
  var description: String
}

func parseArguments(_ arguments: [String]) throws -> (spec: URL, output: URL, module: String) {
  var spec: String?
  var output: String?
  var module: String?
  var index = 0
  while index < arguments.count {
    switch arguments[index] {
    case "--spec":
      index += 1
      spec = arguments[index]
    case "--output":
      index += 1
      output = arguments[index]
    case "--module":
      index += 1
      module = arguments[index]
    default:
      throw CLIError(description: "unknown argument: \(arguments[index])")
    }
    index += 1
  }
  guard let spec, let output, let module else {
    throw CLIError(
      description: "usage: openapi-codegen --spec <path> --output <dir> --module <name>")
  }
  return (
    URL(fileURLWithPath: spec), URL(fileURLWithPath: output, isDirectory: true), module
  )
}

let (specURL, outputURL, moduleName) = try parseArguments(Array(CommandLine.arguments.dropFirst()))

let data = try Data(contentsOf: specURL)
let document = try JSONDecoder().decode(OpenAPI.Document.self, from: data)
let irDocument = try OpenAPIParsing.parseDocument(document)

try FileManager.default.createDirectory(at: outputURL, withIntermediateDirectories: true)

let models = SwiftEmitter.emitModels(irDocument)
try models.write(
  to: outputURL.appendingPathComponent("Models.swift"), atomically: true, encoding: .utf8)

let clientName = "\(moduleName)Client"
let client = SwiftEmitter.emitClient(irDocument, clientName: clientName)
try client.write(
  to: outputURL.appendingPathComponent("\(clientName).swift"), atomically: true, encoding: .utf8)

print(
  "Generated \(irDocument.schemas.count) schemas and \(irDocument.operations.count) operations into \(outputURL.path)"
)
