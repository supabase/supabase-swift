import ConcurrencyExtras
import Foundation
import Mocker
import TestHelpers

@testable import Auth

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

/// An ``AuthClient`` backed by Mocker that records each request it sends.
struct V3TestClient {
  let sut: AuthClient
  let requests = LockIsolated<[URLRequest]>([])

  init(storage: InMemoryLocalStorage = InMemoryLocalStorage()) {
    let sessionConfiguration = URLSessionConfiguration.default
    sessionConfiguration.protocolClasses = [MockingURLProtocol.self]
    let session = URLSession(configuration: sessionConfiguration)

    sut = AuthClient(
      configuration: AuthClient.Configuration(
        url: clientURL,
        headers: ["apikey": "key"],
        localStorage: storage,
        logger: nil,
        fetch: { [requests] request in
          requests.withValue { $0.append(request) }
          return try await session.data(for: request)
        }
      )
    )

    Dependencies[sut.clientID].pkce.generateCodeVerifier = { "verifier" }
    Dependencies[sut.clientID].pkce.generateCodeChallenge = { _ in "challenge" }
  }

  func storeSession(_ session: Session = .validSession) {
    Dependencies[sut.clientID].sessionStorage.store(session)
  }

  var lastRequest: URLRequest? { requests.value.last }

  var lastBody: NSDictionary? { body(at: requests.value.count - 1) }

  func body(at index: Int) -> NSDictionary? {
    guard requests.value.indices.contains(index), let data = requests.value[index].httpBody else {
      return nil
    }
    return try? JSONSerialization.jsonObject(with: data) as? NSDictionary
  }

  func query(at index: Int? = nil) -> [String: String] {
    let request = index.map { requests.value[$0] } ?? requests.value.last
    let items =
      request?.url.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false) }?.queryItems
      ?? []
    return Dictionary(items.map { ($0.name, $0.value ?? "") }, uniquingKeysWith: { $1 })
  }
}

func mock(
  _ path: String, _ method: Mock.HTTPMethod = .post, status: Int = 200, data: Data = Data()
) {
  Mock(
    url: clientURL.appendingPathComponent(path),
    ignoreQuery: true,
    statusCode: status,
    data: [method: data]
  ).register()
}
