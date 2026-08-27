//
//  HTTPFieldNames.swift
//  HTTPRuntime
//
//  Created by Guilherme Souza on 25/08/26.
//
package import HTTPTypes

extension HTTPField.Name {
  /// RFC 7240 `Prefer`. `HTTPTypes` ships no static for this one.
  ///
  /// - Important: Do not add `xClientInfo`, `xRegion` or `xRelayError` here.
  ///   `Sources/Helpers/HTTP/HTTPFields.swift` already declares all three as
  ///   `package`, and two same-named `package` statics on `HTTPField.Name` in
  ///   two modules are ambiguous at any call site importing both.
  package static let prefer = HTTPField.Name("Prefer")!
}
