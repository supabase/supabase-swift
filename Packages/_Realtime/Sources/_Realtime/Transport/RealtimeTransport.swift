import Foundation

public protocol RealtimeTransport: Sendable {
  func connect(to url: URL, headers: [String: String]) async throws -> any RealtimeConnection
}

public protocol RealtimeConnection: Sendable {
  /// Incoming frames from the server. Finishes (possibly with error) when the connection closes.
  var frames: AsyncThrowingStream<TransportFrame, any Error> { get }
  func send(_ frame: TransportFrame) async throws
  func close(code: Int, reason: String) async
}

public enum TransportFrame: Sendable, Equatable {
  case text(String)
  case binary(Data)
}
