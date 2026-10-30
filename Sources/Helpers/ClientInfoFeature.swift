//
//  ClientInfoFeature.swift
//  Supabase
//
//  Created by Guilherme Souza on 27/10/26.
//

/// An SDK feature used to build a request, reported in the `features` parameter of the
/// `X-Client-Info` header.
///
/// Only values defined by the Standard SDK headers spec may be sent.
package struct ClientInfoFeature: RawRepresentable, Hashable, Sendable {
  package let rawValue: String

  package init(rawValue: String) {
    self.rawValue = rawValue
  }

  /// The request was built with the type-safe API.
  package static let typedAPI = ClientInfoFeature(rawValue: "typed-api")

  /// Returns `clientInfo` with `features` merged into its `features` parameter.
  ///
  /// The parameter appears once, last, as a sorted comma-separated list that also keeps any
  /// feature `clientInfo` already listed. The other parameters keep their order and values.
  /// With no `features`, `clientInfo` is returned unchanged.
  package static func clientInfo(
    _ clientInfo: String,
    adding features: Set<ClientInfoFeature>
  ) -> String {
    guard !features.isEmpty else { return clientInfo }

    let key = "features="
    var names = Set(features.map(\.rawValue))
    var parameters: [String] = []
    for parameter in clientInfo.split(separator: ";") {
      let trimmed = parameter.drop(while: \.isWhitespace)
      if trimmed.hasPrefix(key) {
        names.formUnion(trimmed.dropFirst(key.count).split(separator: ",").map(String.init))
      } else {
        parameters.append(String(trimmed))
      }
    }
    parameters.append(key + names.sorted().joined(separator: ","))
    return parameters.joined(separator: "; ")
  }
}
