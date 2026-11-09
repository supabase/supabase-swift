//
//  ClientInfo.swift
//  Supabase
//
//  Created by Guilherme Souza on 09/11/26.
//

/// The `X-Client-Info` value every client sends unless the app sets that header itself.
///
/// The value is `<library>/<version>`, then the platform, its version, and the Swift runtime
/// version. A value the build cannot detect is left out.
package func clientInfo(
  library: String,
  version: String = Helpers.version,
  platform: String? = Helpers.platform,
  platformVersion: String? = Helpers.platformVersion,
  runtimeVersion: String? = Helpers.runtimeVersion
) -> String {
  var parameters = ["\(library)/\(version)"]
  if let platform { parameters.append("platform=\(platform)") }
  if let platformVersion { parameters.append("platform-version=\(platformVersion)") }
  parameters.append("runtime=swift")
  if let runtimeVersion { parameters.append("runtime-version=\(runtimeVersion)") }
  return parameters.joined(separator: "; ")
}
