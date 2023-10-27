import Foundation
@_spi(Internal) import _Helpers

struct EventEmitter: Sendable {
  var attachListener: @Sendable () async -> (id: UUID, stream: AsyncStream<AuthChangeEvent>)
  var emit: @Sendable (_ event: AuthChangeEvent, _ id: UUID?) async -> Void
}

extension EventEmitter {
  func emit(_ event: AuthChangeEvent) async {
    await emit(event, nil)
  }
}

extension EventEmitter {
  static var live: Self = {
    let continuations = ActorIsolated([UUID: AsyncStream<AuthChangeEvent>.Continuation]())

    return Self(
      attachListener: {
        let id = UUID()

        let (stream, continuation) = AsyncStream<AuthChangeEvent>.makeStream()

        continuation.onTermination = { [id] _ in
          continuations.withValue {
            $0[id] = nil
          }
        }

        continuations.withValue {
          $0[id] = continuation
        }

        return (id, stream)
      },
      emit: { event, id in
        if let id {
          continuations.value[id]?.yield(event)
        } else {
          for continuation in continuations.value.values {
            continuation.yield(event)
          }
        }
      }
    )
  }()
}
