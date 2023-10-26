import Foundation
@_spi(Internal) import _Helpers

protocol EventEmitter: Sendable {
  func attachListener() async -> (id: UUID, stream: AsyncStream<AuthChangeEvent>)
  func emit(_ event: AuthChangeEvent, id: UUID?) async
}

extension EventEmitter {
  func emit(_ event: AuthChangeEvent) async {
    await emit(event, id: nil)
  }
}

actor DefaultEventEmitter: EventEmitter {
  deinit {
    continuations.values.forEach {
      $0.finish()
    }
  }

  private(set) var continuations: [UUID: AsyncStream<AuthChangeEvent>.Continuation] = [:]

  func attachListener() -> (id: UUID, stream: AsyncStream<AuthChangeEvent>) {
    let id = UUID()

    let (stream, continuation) = AsyncStream<AuthChangeEvent>.makeStream()

    continuation.onTermination = { [self, id] _ in
      Task(priority: .high) {
        await removeStream(at: id)
      }
    }

    continuations[id] = continuation

    return (id, stream)
  }

  func emit(_ event: AuthChangeEvent, id: UUID? = nil) {
    if let id {
      continuations[id]?.yield(event)
    } else {
      for continuation in continuations.values {
        continuation.yield(event)
      }
    }
  }

  private func removeStream(at id: UUID) {
    self.continuations[id] = nil
  }
}
