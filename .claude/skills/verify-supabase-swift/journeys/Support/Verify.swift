// Shared support for verification journeys. `verify.sh drive` copies this file next to the
// journey's main.swift. Journeys call the SDK's public API only, like an app would.
import Foundation
import Supabase

@MainActor
enum Verify {
  static let env = ProcessInfo.processInfo.environment

  static let url: URL = {
    guard let raw = env["SUPABASE_URL"], let url = URL(string: raw) else {
      fatalError("SUPABASE_URL is not set; run journeys through `verify.sh drive`")
    }
    return url
  }()

  static let publishableKey = env["SUPABASE_PUBLISHABLE_KEY"] ?? ""
  static let serviceRoleKey = env["SUPABASE_SERVICE_ROLE_KEY"] ?? ""
  static let runID = env["VERIFY_RUN_ID"] ?? "adhoc"

  static let evidenceDir: URL = {
    let path = env["VERIFY_EVIDENCE_DIR"] ?? FileManager.default.currentDirectoryPath
    return URL(fileURLWithPath: path, isDirectory: true)
  }()

  private static var checks = 0
  private static var failures: [String] = []

  /// A client as an app would build it, with an in-memory session store so runs never share state.
  static func client(key: String? = nil) -> SupabaseClient {
    SupabaseClient(
      supabaseURL: url,
      supabaseKey: key ?? publishableKey,
      options: SupabaseClientOptions(auth: .init(storage: MemoryAuthStorage()))
    )
  }

  /// A value unique to this run, so repeated runs on one stack never collide.
  static func unique(_ prefix: String) -> String {
    "\(prefix)-\(runID)-\(UUID().uuidString.prefix(8).lowercased())"
  }

  static func step(_ id: String, _ detail: String) {
    print("STEP \(id) | \(detail)")
  }

  static func check(_ id: String, _ condition: Bool, _ detail: String) {
    checks += 1
    if condition {
      print("PASS \(id) | \(detail)")
    } else {
      failures.append(id)
      print("FAIL \(id) | \(detail)")
    }
  }

  /// Runs one step; a thrown error fails the step instead of aborting the journey.
  static func attempt<T>(_ id: String, _ body: () async throws -> T) async -> T? {
    do {
      return try await body()
    } catch {
      check(id, false, "threw \(String(reflecting: error))")
      return nil
    }
  }

  /// Writes an evidence file into the run's evidence directory and logs its path. A write that
  /// fails is a failed check, so a run never passes without the evidence it claims.
  static func save(_ name: String, _ value: some Encodable) {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    encoder.dateEncodingStrategy = .iso8601
    do {
      let file = evidenceDir.appendingPathComponent(name)
      try encoder.encode(value).write(to: file)
      print("SAVE \(file.path)")
    } catch {
      check("save \(name)", false, "could not save: \(error)")
    }
  }

  /// Waits for `body` with a deadline, so a missing realtime event fails instead of hanging.
  ///
  /// On timeout the group cancels `body` and waits for it to return, so `body` must stop on
  /// cancellation. Iterating an `AsyncStream` does. Awaiting another task's `value` does not:
  /// wrap it in `withTaskCancellationHandler` and cancel that task.
  static func within<T: Sendable>(
    seconds: Double,
    _ body: @escaping @Sendable () async throws -> T
  ) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
      group.addTask { try await body() }
      group.addTask {
        try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
        throw TimedOut(seconds: seconds)
      }
      defer { group.cancelAll() }
      guard let first = try await group.next() else { throw TimedOut(seconds: seconds) }
      return first
    }
  }

  struct TimedOut: Error { let seconds: Double }

  static func finish() -> Never {
    let result = failures.isEmpty ? "PASS" : "FAIL"
    print("RESULT \(result) | \(checks) checks, \(failures.count) failed \(failures)")
    exit(failures.isEmpty ? 0 : 1)
  }
}

final class MemoryAuthStorage: AuthLocalStorage, @unchecked Sendable {
  private let lock = NSLock()
  private var values: [String: Data] = [:]

  func store(key: String, value: Data) throws { lock.withLock { values[key] = value } }
  func retrieve(key: String) throws -> Data? { lock.withLock { values[key] } }
  func remove(key: String) throws { lock.withLock { values[key] = nil } }
}
