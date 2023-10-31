import Foundation
@_spi(Internal) import _Helpers

struct EventEmitter: Sendable {
  var attachListener: @Sendable () async -> (id: UUID, stream: AsyncStream<(event: AuthChangeEvent, session: Session?)>)
  var emit: @Sendable (_ event: AuthChangeEvent, _ session: Session?, _ id: UUID?) async -> Void
}

extension EventEmitter {
  func emit(_ event: AuthChangeEvent, session: Session?) async {
    await emit(event, session, nil)
  }
}

extension EventEmitter {
  static var live: Self = {
    let continuations = ActorIsolated([UUID: AsyncStream<(event: AuthChangeEvent, session: Session?)>.Continuation]())

    return Self(
      attachListener: {
        let id = UUID()

        let (stream, continuation) = AsyncStream<(event: AuthChangeEvent, session: Session?)>.makeStream()

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
      emit: { event, session, id in
        NotificationCenter.default.post(
          name: GoTrueClient.didChangeAuthStateNotification,
          object: nil
        )
        if let id {
          continuations.value[id]?.yield((event, session))
        } else {
          for continuation in continuations.value.values {
            continuation.yield((event, session))
          }
        }
      }
    )
  }()
}
