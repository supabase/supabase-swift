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
  static var mock = Dependencies(
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

extension HTTPResponse {
  static func stub(
    _ body: String = "",
    code: Int = 200,
    headers: [String: String]? = nil
  ) -> HTTPResponse {
    HTTPResponse(
      data: body.data(using: .utf8)!,
      response: HTTPURLResponse(
        url: clientURL,
        statusCode: code,
        httpVersion: nil,
        headerFields: headers
      )!
    )
  }

  static func stub(
    fromFileName fileName: String,
    code: Int = 200,
    headers: [String: String]? = nil
  ) -> HTTPResponse {
    HTTPResponse(
      data: json(named: fileName),
      response: HTTPURLResponse(
        url: clientURL,
        statusCode: code,
        httpVersion: nil,
        headerFields: headers
      )!
    )
  }

  static func stub(
    _ value: some Encodable,
    code: Int = 200,
    headers: [String: String]? = nil
  ) -> HTTPResponse {
    HTTPResponse(
      data: try! AuthClient.Configuration.jsonEncoder.encode(value),
      response: HTTPURLResponse(
        url: clientURL,
        statusCode: code,
        httpVersion: nil,
        headerFields: headers
      )!
    )
  }
}

enum MockData {
  static let listUsersResponse = try! Data(
    contentsOf: Bundle.module.url(forResource: "list-users-response", withExtension: "json")!
  )

  static let session = try! Data(
    contentsOf: Bundle.module.url(forResource: "session", withExtension: "json")!
  )

  static let user = try! Data(
    contentsOf: Bundle.module.url(forResource: "user", withExtension: "json")!
  )

  static let anonymousSignInResponse = try! Data(
    contentsOf: Bundle.module.url(forResource: "anonymous-sign-in-response", withExtension: "json")!
  )
}
