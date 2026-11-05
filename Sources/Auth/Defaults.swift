import ConcurrencyExtras
import Foundation
import HTTPTypes

extension AuthClient.Configuration {
  static let jsonEncoder: JSONEncoder = {
    let encoder = JSONEncoder.supabase()
    encoder.keyEncodingStrategy = .convertToSnakeCase
    return encoder
  }()

  static let jsonDecoder: JSONDecoder = {
    let decoder = JSONDecoder.supabase()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    return decoder
  }()

  /// Sent unless the configured headers set the same name.
  static let defaultHeaders: HTTPFields = [
    HTTPField.Name.xClientInfo: "auth-swift/\(version)"
  ]
}
