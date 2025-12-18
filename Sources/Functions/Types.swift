import Foundation
import HTTPTypes

/// An error type representing various errors that can occur while invoking functions.
public enum FunctionsError: Error, LocalizedError {
  /// Error indicating a relay error while invoking the Edge Function.
  case relayError
  /// Error indicating a non-2xx status code returned by the Edge Function.
  case httpError(code: Int, data: Data)

  /// A localized description of the error.
  public var errorDescription: String? {
    switch self {
    case .relayError:
      "Relay Error invoking the Edge Function"
    case .httpError(let code, _):
      "Edge Function returned a non-2xx status code: \(code)"
    }
  }
}

/// A region to invoke the Edge Function in.
public struct FunctionRegion: RawRepresentable, Sendable {
  /// The raw value of the region.
  public let rawValue: String

  /// Initializes a new instance of `FunctionRegion` with a raw value.
  ///
  /// - Parameter rawValue: The raw value of the region.
  public init(rawValue: String) {
    self.rawValue = rawValue
  }

  public static let apNortheast1 = FunctionRegion(rawValue: "ap-northeast-1")
  public static let apNortheast2 = FunctionRegion(rawValue: "ap-northeast-2")
  public static let apSouth1 = FunctionRegion(rawValue: "ap-south-1")
  public static let apSoutheast1 = FunctionRegion(rawValue: "ap-southeast-1")
  public static let apSoutheast2 = FunctionRegion(rawValue: "ap-southeast-2")
  public static let caCentral1 = FunctionRegion(rawValue: "ca-central-1")
  public static let euCentral1 = FunctionRegion(rawValue: "eu-central-1")
  public static let euWest1 = FunctionRegion(rawValue: "eu-west-1")
  public static let euWest2 = FunctionRegion(rawValue: "eu-west-2")
  public static let euWest3 = FunctionRegion(rawValue: "eu-west-3")
  public static let saEast1 = FunctionRegion(rawValue: "sa-east-1")
  public static let usEast1 = FunctionRegion(rawValue: "us-east-1")
  public static let usWest1 = FunctionRegion(rawValue: "us-west-1")
  public static let usWest2 = FunctionRegion(rawValue: "us-west-2")
}
extension FunctionRegion: ExpressibleByStringLiteral {
  public init(stringLiteral value: String) {
    self.init(rawValue: value)
  }
}
