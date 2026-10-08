//
//  Typegen.swift
//  SupabaseTypegen
//
//  Created by Guilherme Souza on 08/10/26.
//

import Foundation

/// The outcome of one run: what `main.swift` writes to the standard streams and the exit code.
struct RunResult: Equatable {
  var exitCode: Int32
  var standardOutput = ""
  var standardError = ""
}

/// The exit codes of `sysexits.h` the generator uses.
enum ExitCode {
  static let success: Int32 = 0
  static let usage: Int32 = 64
  static let dataError: Int32 = 65
  static let software: Int32 = 70
  static let cannotCreate: Int32 = 73
}

let usage = """
  Usage: supabase-typegen [--schema <name>]... [--output <path>] [--access-control public|internal]

  Reads a GeneratorMetadata document (version 1) from standard input and writes Swift @Table
  structs.

    --schema <name>            Generate this schema. Repeatable. Default: every schema.
    --output <path>            Write to this file. Default: -, standard output.
    --access-control <level>   public or internal. Default: internal.
    -h, --help                 Print this message.

  """

struct Options: Equatable {
  enum AccessControl: String {
    case `public`, `internal`
  }

  var schemas: [String] = []
  var output = "-"
  var accessControl = AccessControl.internal
  var help = false

  struct UsageError: Error {
    var message: String
  }

  /// Parses the arguments after the executable name. Accepts `--option value` and `--option=value`.
  init(arguments: [String]) throws(UsageError) {
    var remaining = arguments[...]
    while let argument = remaining.popFirst() {
      if argument == "-h" || argument == "--help" {
        help = true
        continue
      }
      guard argument.hasPrefix("--") else {
        throw UsageError(message: "unexpected argument '\(argument)'")
      }
      let parts = argument.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
      let name = String(parts[0])
      guard ["--schema", "--output", "--access-control"].contains(name) else {
        throw UsageError(message: "unknown option '\(name)'")
      }
      guard let value = parts.count == 2 ? String(parts[1]) : remaining.popFirst(),
        !value.isEmpty
      else {
        throw UsageError(message: "option '\(name)' needs a value")
      }
      switch name {
      case "--schema":
        schemas.append(value)
      case "--output":
        output = value
      default:
        guard let level = AccessControl(rawValue: value) else {
          throw UsageError(
            message: "option '--access-control' expects public or internal, got '\(value)'")
        }
        accessControl = level
      }
    }
  }
}

/// Runs the generator. Reads standard input only once the arguments are valid, so `--help` and a
/// bad option do not wait for input.
func run(arguments: [String], standardInput: () -> Data) -> RunResult {
  let options: Options
  do {
    options = try Options(arguments: arguments)
  } catch {
    return RunResult(
      exitCode: ExitCode.usage, standardError: "supabase-typegen: \(error.message)\n\n\(usage)")
  }
  if options.help {
    return RunResult(exitCode: ExitCode.success, standardOutput: usage)
  }

  let metadata: GeneratorMetadata
  do {
    metadata = try decodeGeneratorMetadata(standardInput())
  } catch {
    return RunResult(exitCode: ExitCode.dataError, standardError: "supabase-typegen: \(error)\n")
  }

  let documentSchemas = Set(metadata.schemas.map(\.name))
  let unknown = options.schemas.filter { !documentSchemas.contains($0) }
  if !unknown.isEmpty {
    return RunResult(
      exitCode: ExitCode.usage,
      standardError: """
        supabase-typegen: the document has no schema \(quoted(unknown)); \
        it has \(quoted(documentSchemas.sorted()))

        \(usage)
        """
    )
  }

  let plan: FilePlan
  let file: String
  do {
    plan = try FilePlan(DatabaseModel(metadata, schemas: options.schemas))
    file = try plan.render(accessControl: options.accessControl)
  } catch let error as FilePlan.TypeNameClash {
    return RunResult(
      exitCode: ExitCode.dataError,
      standardError: error.description.split(separator: "\n").map { "supabase-typegen: \($0)\n" }
        .joined()
    )
  } catch {
    return RunResult(
      exitCode: ExitCode.software, standardError: "supabase-typegen: internal error: \(error)\n")
  }
  let notes = plan.notes.map { "supabase-typegen: note: \($0)\n" }.joined()

  if options.output == "-" {
    return RunResult(exitCode: ExitCode.success, standardOutput: file, standardError: notes)
  }
  do {
    try Data(file.utf8).write(to: URL(fileURLWithPath: options.output), options: .atomic)
  } catch {
    return RunResult(
      exitCode: ExitCode.cannotCreate,
      standardError:
        "supabase-typegen: cannot write '\(options.output)': \(error.localizedDescription)\n"
    )
  }
  return RunResult(exitCode: ExitCode.success, standardError: notes)
}

private func quoted(_ names: [String]) -> String {
  names.map { "'\($0)'" }.joined(separator: ", ")
}

/// A document the generator cannot read. Its description is the message on standard error.
struct DataError: Error, CustomStringConvertible {
  var description: String
}

let supportedVersion = "1"

/// Decodes `data`, checking `version` first so a document of another version is reported as such
/// rather than as a missing field.
func decodeGeneratorMetadata(_ data: Data) throws(DataError) -> GeneratorMetadata {
  struct Header: Decodable {
    var version: Version

    /// postgrest-typegen writes the number `1`; a string `"1"` is accepted too.
    struct Version: Decodable {
      var text: String
      init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let number = try? container.decode(Int.self) {
          text = String(number)
        } else {
          text = try container.decode(String.self)
        }
      }
    }
  }

  let decoder = JSONDecoder()
  decoder.keyDecodingStrategy = .convertFromSnakeCase
  do {
    let version = try decoder.decode(Header.self, from: data).version.text
    guard version == supportedVersion else {
      throw DataError(
        description: "GeneratorMetadata version \(version) is not supported; "
          + "this generator reads version \(supportedVersion)"
      )
    }
    return try decoder.decode(GeneratorMetadata.self, from: data)
  } catch let error as DataError {
    throw error
  } catch let error as DecodingError {
    throw DataError(description: "not a GeneratorMetadata document: \(describe(error))")
  } catch {
    throw DataError(description: "not a GeneratorMetadata document: \(error.localizedDescription)")
  }
}

private func describe(_ error: DecodingError) -> String {
  // Top-level keys are camelCase in the document; nested keys are snake_case, which
  // `.convertFromSnakeCase` turned into camelCase.
  func path(_ codingPath: [any CodingKey]) -> String {
    codingPath.enumerated().map { index, key in
      if let position = key.intValue { return "[\(position)]" }
      let name = index == 0 ? key.stringValue : snakeCase(key.stringValue)
      return index == 0 ? name : ".\(name)"
    }.joined()
  }
  func snakeCase(_ name: String) -> String {
    name.map { $0.isUppercase ? "_\($0.lowercased())" : String($0) }.joined()
  }
  switch error {
  case .keyNotFound(let key, let context):
    return "\(path(context.codingPath + [key])) is missing"
  case .typeMismatch(_, let context), .valueNotFound(_, let context),
    .dataCorrupted(let context):
    let location = context.codingPath.isEmpty ? "" : "\(path(context.codingPath)): "
    return "\(location)\(context.debugDescription)"
  @unknown default:
    return "\(error)"
  }
}
