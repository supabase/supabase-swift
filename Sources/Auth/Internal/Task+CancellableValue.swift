import ConcurrencyExtras

/// Waits for the value of `task`, but throws `CancellationError` as soon as the caller is
/// cancelled. Cancelling the caller does not cancel `task`, so other callers that wait for the
/// same task still get its result.
func cancellableValue<Success: Sendable>(
  of task: Task<Success, any Error>
) async throws -> Success {
  let waiter = LockIsolated(CancellableWaiter<Success>.pending)
  let resume = { @Sendable (result: Result<Success, any Error>) in
    let continuation = waiter.withValue { state -> CheckedContinuation<Success, any Error>? in
      defer { state = .finished }
      guard case .suspended(let continuation) = state else { return nil }
      return continuation
    }
    continuation?.resume(with: result)
  }

  return try await withTaskCancellationHandler {
    try await withCheckedThrowingContinuation { continuation in
      let cancelled = waiter.withValue { state in
        guard case .pending = state else { return true }
        state = .suspended(continuation)
        return false
      }
      if cancelled {
        continuation.resume(throwing: CancellationError())
        return
      }
      Task { resume(await task.result) }
    }
  } onCancel: {
    resume(.failure(CancellationError()))
  }
}

private enum CancellableWaiter<Success: Sendable> {
  case pending
  case suspended(CheckedContinuation<Success, any Error>)
  case finished
}
