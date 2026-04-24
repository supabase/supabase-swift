import Clocks
import Foundation

public struct Configuration: Sendable {
  public var heartbeat: Duration = .seconds(25)
  public var joinTimeout: Duration = .seconds(10)
  public var leaveTimeout: Duration = .seconds(10)
  public var broadcastAckTimeout: Duration = .seconds(5)
  public var reconnection: ReconnectionPolicy = .exponentialBackoff(
    initial: .seconds(1), max: .seconds(30)
  )
  /// Socket stays open this long after the last channel leaves. `.zero` = immediate close.
  public var disconnectOnEmptyChannelsAfter: Duration = .seconds(50)
  public var handleAppLifecycle: Bool = Configuration.defaultHandleAppLifecycle
  public var protocolVersion: RealtimeProtocolVersion = .v2
  public var clock: any Clock<Duration> = ContinuousClock()
  public var headers: [String: String] = [:]
  public var logger: (any RealtimeLogger)? = nil
  public var urlSession: URLSession = .shared
  public var decoder: JSONDecoder = {
    let d = JSONDecoder()
    d.dateDecodingStrategy = .iso8601
    return d
  }()
  public var encoder: JSONEncoder = {
    let e = JSONEncoder()
    e.dateEncodingStrategy = .iso8601
    return e
  }()

  public static let `default` = Configuration()
  public init() {}

  public init(_ configure: (inout Configuration) -> Void) {
    var c = Configuration()
    configure(&c)
    self = c
  }

  #if os(iOS) || os(macOS) || os(tvOS) || os(visionOS)
    static let defaultHandleAppLifecycle = true
  #else
    static let defaultHandleAppLifecycle = false
  #endif
}

public enum RealtimeProtocolVersion: String, Sendable {
  case v1 = "1.0.0"
  case v2 = "2.0.0"
}
