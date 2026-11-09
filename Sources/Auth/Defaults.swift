import ConcurrencyExtras
import Foundation
import HTTPTypes

extension AuthClient.Configuration {
  static let jsonEncoder = JSONEncoder.supabase()

  static let jsonDecoder = JSONDecoder.supabase()

  /// Sent unless the configured headers set the same name.
  static let defaultHeaders: HTTPFields = [
    .xClientInfo: clientInfo(library: "auth-swift")
  ]
}
