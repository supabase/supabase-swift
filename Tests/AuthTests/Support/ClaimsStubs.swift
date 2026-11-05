import Foundation
import TestHelpers

@testable import Auth

extension RecordingTransport {
  /// Answers `GET .well-known/jwks.json`, on any host, with a JWKS that holds `key`.
  func stubJWKS(_ key: JWK) throws {
    let fields: [String: String?] = [
      "kty": key.kty, "alg": key.alg, "kid": key.kid, "crv": key.crv, "x": key.x, "y": key.y,
    ]
    let data = try JSONSerialization.data(
      withJSONObject: ["keys": [fields.compactMapValues { $0 }]]
    )
    stub(.get, ".well-known/jwks.json", data: data)
  }

  /// Answers `GET user` with the `user` fixture.
  func stubUser() throws {
    let user = User(fromMockNamed: "user")
    stub(.get, "user", data: try AuthClient.Configuration.jsonEncoder.encode(user))
  }

  /// The number of JWKS requests received, only those sent to `host` when it is given.
  func jwksRequestCount(host: String? = nil) -> Int {
    requests(.get, ".well-known/jwks.json")
      .filter { host == nil || $0.head.url?.host == host }
      .count
  }

  /// The number of `GET user` requests received.
  var userRequestCount: Int {
    requests(.get, "user").count
  }
}
