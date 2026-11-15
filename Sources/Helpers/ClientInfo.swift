//
//  ClientInfo.swift
//  Supabase
//
//  Created by Guilherme Souza on 09/11/26.
//

import Foundation

/// The `X-Client-Info` value every client sends unless the app sets that header itself.
///
/// The value is `<library>/<version>`, then the platform, its version, and the Swift runtime
/// version. A value the build cannot detect, or that is empty after trimming whitespace, is left
/// out. Each value is percent-encoded as ``clientInfoParameterValue(_:)`` describes.
package func clientInfo(
  library: String,
  version: String = Helpers.version,
  platform: String? = Helpers.platform,
  platformVersion: String? = Helpers.platformVersion,
  runtimeVersion: String? = Helpers.runtimeVersion
) -> String {
  var parameters = ["\(library)/\(version)"]
  func append(_ key: String, _ value: String?) {
    if let value = value.flatMap(clientInfoParameterValue) { parameters.append("\(key)=\(value)") }
  }
  append("platform", platform)
  append("platform-version", platformVersion)
  parameters.append("runtime=swift")
  append("runtime-version", runtimeVersion)
  return parameters.joined(separator: "; ")
}

private let clientInfoValueAllowed = CharacterSet(charactersIn: " "..."~")
  .subtracting(CharacterSet(charactersIn: ";%"))

/// `value` trimmed of whitespace, with every character outside printable ASCII, every `;` and
/// every `%` percent-encoded as UTF-8, so it cannot end the parameter or break the header. `nil`
/// when the trimmed value is empty.
func clientInfoParameterValue(_ value: String) -> String? {
  let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
  guard !trimmed.isEmpty else { return nil }
  return trimmed.addingPercentEncoding(withAllowedCharacters: clientInfoValueAllowed)
}
