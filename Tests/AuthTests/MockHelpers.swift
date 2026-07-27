import ConcurrencyExtras
import Foundation
import TestHelpers

@testable import Auth

func json(named name: String) -> Data {
  let url = Bundle.module.url(forResource: name, withExtension: "json")
  return try! Data(contentsOf: url!)
}

extension Decodable {
  init(fromMockNamed name: String) {
    self = try! AuthClient.Configuration.jsonDecoder.decode(Self.self, from: json(named: name))
  }
}

extension Dependencies {
  static let mock = Dependencies(
    configuration: AuthClient.Configuration(
      url: URL(string: "https://project-id.supabase.com")!,
      localStorage: InMemoryLocalStorage(),
      logger: nil
    ),
    http: HTTPClientMock(),
    api: APIClient(clientID: AuthClientID()),
    codeVerifierStorage: CodeVerifierStorage.mock,
    sessionStorage: SessionStorage.live(clientID: AuthClientID()),
    sessionManager: SessionManager.live(clientID: AuthClientID())
  )
}

extension CodeVerifierStorage {
  static var mock: CodeVerifierStorage {
    let code = LockIsolated<String?>(nil)

    return Self(
      get: { code.value },
      set: { code.setValue($0) }
    )
  }
}
