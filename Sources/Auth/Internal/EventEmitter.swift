import Foundation

struct EventEmitter: Sendable {
  var attachListener: @Sendable () -> (
    id: UUID,
    stream: AsyncStream<(event: AuthChangeEvent, session: Session?)>
  )
  var emit: @Sendable (_ event: AuthChangeEvent, _ session: Session?, _ id: UUID?) -> Void
}

extension EventEmitter {
  func emit(_ event: AuthChangeEvent, session: Session?) {
    emit(event, session, nil)
  }
}

extension EventEmitter {
  static var live: Self = {
    let continuations = LockedState(
      initialState: [UUID: AsyncStream<(event: AuthChangeEvent, session: Session?)>.Continuation]()
    )

    return Self(
      attachListener: {
        let id = UUID()

        let (stream, continuation) = AsyncStream<(event: AuthChangeEvent, session: Session?)>
          .makeStream()

        continuation.onTermination = { [id] _ in
          continuations.withLock {
            $0[id] = nil
          }
        }

        continuations.withLock {
          $0[id] = continuation
        }

        return (id, stream)
      },
      emit: { event, session, id in
        NotificationCenter.default.post(
          name: AuthClient.didChangeAuthStateNotification,
          object: nil,
          userInfo: [
            AuthClient.authChangeEventInfoKey: event,
            AuthClient.authChangeSessionInfoKey: session as Any,
          ]
        )
        if let id {
          _ = continuations.withLock {
            $0[id]?.yield((event, session))
          }
        } else {
          for continuation in continuations.withLock(\.values) {
            continuation.yield((event, session))
          }
        }
      }
    )
  }()
}
