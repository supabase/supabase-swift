import Foundation

/// Runs one operation per key and replays its result, including a failure, to later callers.
///
/// A redirect URL can reach the client more than once, for example from both a scene delegate and
/// `onOpenURL`. A PKCE code is single-use, so the second exchange would fail and mask the first.
actor RedirectDeduplicator<Value: Sendable> {
  private let capacity: Int
  private var tasks: [String: Task<Value, any Error>] = [:]
  private var order: [String] = []

  init(capacity: Int = 8) {
    self.capacity = capacity
  }

  func value(
    for key: String,
    _ operation: @escaping @Sendable () async throws -> Value
  ) async throws -> Value {
    if let existing = tasks[key] {
      return try await existing.value
    }

    // Stored before the first suspension so a concurrent caller finds it. It is unstructured so
    // cancelling one caller does not cancel the others.
    let task = Task { try await operation() }
    tasks[key] = task
    order.append(key)
    if order.count > capacity {
      tasks.removeValue(forKey: order.removeFirst())
    }
    return try await task.value
  }
}
