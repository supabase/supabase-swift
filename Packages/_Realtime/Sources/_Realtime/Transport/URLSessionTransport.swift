import Foundation

public struct URLSessionTransport: RealtimeTransport {
  private let session: URLSession

  public init(session: URLSession = .shared) {
    self.session = session
  }

  public func connect(to url: URL, headers: [String: String]) async throws -> any RealtimeConnection {
    var request = URLRequest(url: url)
    for (key, value) in headers {
      request.setValue(value, forHTTPHeaderField: key)
    }
    let task = session.webSocketTask(with: request)
    task.resume()
    return URLSessionConnection(task: task)
  }
}

private final class URLSessionConnection: RealtimeConnection, @unchecked Sendable {
  // @unchecked Sendable: all stored properties are `let`; URLSessionWebSocketTask's
  // send/cancel APIs are thread-safe.
  private let task: URLSessionWebSocketTask
  private let receiveTask: Task<Void, Never>
  let frames: AsyncThrowingStream<TransportFrame, any Error>
  private let continuation: AsyncThrowingStream<TransportFrame, any Error>.Continuation

  init(task: URLSessionWebSocketTask) {
    self.task = task
    let (stream, cont) = AsyncThrowingStream<TransportFrame, any Error>.makeStream()
    self.frames = stream
    self.continuation = cont
    let wsTask = task
    let c = cont
    self.receiveTask = Task {
      do {
        while true {
          let message = try await wsTask.receive()
          switch message {
          case .string(let text): c.yield(.text(text))
          case .data(let data): c.yield(.binary(data))
          @unknown default: break
          }
        }
      } catch {
        c.finish(throwing: error)
      }
    }
  }

  deinit {
    receiveTask.cancel()
    task.cancel(with: .normalClosure, reason: nil)
  }

  func send(_ frame: TransportFrame) async throws {
    switch frame {
    case .text(let text): try await task.send(.string(text))
    case .binary(let data): try await task.send(.data(data))
    }
  }

  func close(code: Int, reason: String) async {
    receiveTask.cancel()
    task.cancel(with: .normalClosure, reason: reason.data(using: .utf8))
  }
}
