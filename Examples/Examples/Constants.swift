//
//  Constants.swift
//  Examples
//
//  Created by Guilherme Souza on 15/12/23.
//

import Foundation

enum Constants {
  static let redirectToURL = URL(string: "com.supabase.swift-examples://")!

  /// Relying-party identifier used by the WebAuthn / passkey examples.
  ///
  /// To actually complete a passkey ceremony on-device this must be a domain you control, and that
  /// domain must:
  ///   1. be listed in `Examples.entitlements` under `webcredentials:` (Associated Domains), and
  ///   2. host an `apple-app-site-association` file granting this app's team+bundle the
  ///      `webcredentials` service.
  /// See: https://developer.apple.com/documentation/xcode/supporting-associated-domains
  static let webAuthnRPID = "example.com"
}

extension URL {
  init?(scheme: String) {
    var components = URLComponents()
    components.scheme = scheme

    guard let url = components.url else {
      return nil
    }

    self = url
  }
}
