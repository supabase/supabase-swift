//
//  TypegenTests.swift
//  SupabaseTypegenTests
//
//  Created by Guilherme Souza on 08/10/26.
//

import Foundation
import Testing

@testable import SupabaseTypegen

enum Fixture {
  static func data(_ name: String) -> Data {
    let url = Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures")!
    return try! Data(contentsOf: url)
  }

  static let integration = data("generator_metadata")
  static let postgrestTypegen = data("postgrest_typegen_metadata")

  /// The integration fixture with `edit` applied to its top-level JSON object.
  static func integration(_ edit: (inout [String: Any]) -> Void) -> Data {
    var object = try! JSONSerialization.jsonObject(with: integration) as! [String: Any]
    edit(&object)
    return try! JSONSerialization.data(withJSONObject: object)
  }
}

@Suite
struct TypegenTests {
  private func run(_ arguments: String..., input: Data = Fixture.integration) -> RunResult {
    SupabaseTypegen.run(arguments: arguments) { input }
  }

  @Test(arguments: [Fixture.integration, Fixture.postgrestTypegen])
  func validDocumentWritesTheFileToStandardOutput(document: Data) {
    #expect(
      run(input: document)
        == RunResult(exitCode: 0, standardOutput: "import PostgrestMacros\n"))
  }

  @Test
  func notJSONIsADataError() {
    let result = run(input: Data("not json".utf8))
    #expect(result.exitCode == 65)
    #expect(result.standardOutput.isEmpty)
    #expect(result.standardError.hasPrefix("supabase-typegen: not a GeneratorMetadata document"))
  }

  @Test
  func emptyInputIsADataError() {
    #expect(run(input: Data()).exitCode == 65)
  }

  @Test
  func missingCollectionIsADataErrorNamingIt() {
    let result = run(input: Fixture.integration { $0["columns"] = nil })
    #expect(result.exitCode == 65)
    #expect(result.standardError.contains("columns is missing"))
  }

  @Test
  func missingNestedFieldIsADataErrorNamingItsPath() {
    let result = run(
      input: Fixture.integration { object in
        var columns = object["columns"] as! [[String: Any]]
        columns[2]["table_id"] = nil
        object["columns"] = columns
      })
    #expect(result.exitCode == 65)
    #expect(result.standardError.contains("columns[2].table_id is missing"))
  }

  @Test
  func missingVersionIsADataError() {
    let result = run(input: Fixture.integration { $0["version"] = nil })
    #expect(result.exitCode == 65)
    #expect(result.standardError.contains("version is missing"))
  }

  @Test(arguments: [2, "2", "1.0"] as [any Sendable])
  func otherVersionIsADataErrorNamingTheSupportedOne(version: any Sendable) {
    let result = run(input: Fixture.integration { $0["version"] = version })
    #expect(
      result
        == RunResult(
          exitCode: 65,
          standardError:
            "supabase-typegen: GeneratorMetadata version \(version) is not supported; "
            + "this generator reads version 1\n"
        ))
  }

  @Test
  func versionAsStringIsAccepted() {
    #expect(run(input: Fixture.integration { $0["version"] = "1" }).exitCode == 0)
  }

  @Test(arguments: [
    (["--bogus"], "unknown option '--bogus'"),
    (["--bogus=1"], "unknown option '--bogus'"),
    (["--schema"], "option '--schema' needs a value"),
    (["--output="], "option '--output' needs a value"),
    (
      ["--access-control", "private"],
      "option '--access-control' expects public or internal, got 'private'"
    ),
    (["public"], "unexpected argument 'public'"),
    (["--schema", "nope"], "the document has no schema 'nope'; it has 'public'"),
  ])
  func badOptionPrintsUsageWithExitCode64(arguments: [String], message: String) {
    let result = SupabaseTypegen.run(arguments: arguments) { Fixture.integration }
    #expect(
      result
        == RunResult(exitCode: 64, standardError: "supabase-typegen: \(message)\n\n\(usage)"))
  }

  @Test
  func badOptionDoesNotReadStandardInput() {
    _ = SupabaseTypegen.run(arguments: ["--bogus"]) {
      Issue.record("read standard input")
      return Data()
    }
  }

  @Test
  func helpPrintsUsageWithoutReadingStandardInput() {
    let result = SupabaseTypegen.run(arguments: ["--help"]) {
      Issue.record("read standard input")
      return Data()
    }
    #expect(result == RunResult(exitCode: 0, standardOutput: usage))
  }

  @Test
  func outputWritesTheFile() throws {
    let url = FileManager.default.temporaryDirectory
      .appendingPathComponent("\(UUID().uuidString).swift")
    defer { try? FileManager.default.removeItem(at: url) }

    #expect(run("--output", url.path) == RunResult(exitCode: 0))
    #expect(try String(contentsOf: url, encoding: .utf8) == "import PostgrestMacros\n")
  }

  @Test
  func outputThatCannotBeWrittenIsExitCode73() {
    let result = run("--output", "/nonexistent-directory/Generated.swift")
    #expect(result.exitCode == 73)
    #expect(result.standardError.hasPrefix("supabase-typegen: cannot write"))
  }

  @Test
  func optionsDefaults() throws {
    let options = try Options(arguments: [])
    #expect(options.schemas == [])
    #expect(options.output == "-")
    #expect(options.accessControl == .internal)
    #expect(!options.help)
  }

  @Test
  func optionsParseBothSpellings() throws {
    let options = try Options(arguments: [
      "--schema", "public", "--schema=inventory", "--output=Generated.swift",
      "--access-control", "public",
    ])
    #expect(options.schemas == ["public", "inventory"])
    #expect(options.output == "Generated.swift")
    #expect(options.accessControl == .public)
  }
}
