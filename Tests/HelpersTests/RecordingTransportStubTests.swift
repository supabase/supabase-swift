import Foundation
import HTTPTypes
import Helpers
import TestHelpers
import Testing

struct RecordingTransportStubTests {
  let baseURL = URL(string: "http://localhost:54321/rest/v1")!

  @Test
  func stubMatchesMethodAndPathAndIgnoresUnlistedQueryItems() async throws {
    let transport = RecordingTransport()
    transport.stub(.get, baseURL.appendingPathComponent("users"), data: Data("[]".utf8))

    var url = baseURL.appendingPathComponent("users")
    url.append(queryItems: [URLQueryItem(name: "select", value: "*")])
    let (response, body) = try await transport.send(HTTPRequest(method: .get, url: url), body: nil)

    #expect(response.status == .ok)
    #expect(response.headerFields[.contentType] == "application/json")
    #expect(try await Data(collecting: try #require(body), upTo: .max) == Data("[]".utf8))
    #expect(transport.requests(.get, baseURL.appendingPathComponent("users")).count == 1)
  }

  @Test
  func stubWithQueryOnlyMatchesRequestsThatHaveThoseItems() async throws {
    let transport = RecordingTransport()
    transport.stub(.get, baseURL.appendingPathComponent("users"), query: ["id": "eq.1"])
    transport.stub(.get, baseURL.appendingPathComponent("users"), status: .notFound)

    var url = baseURL.appendingPathComponent("users")
    url.append(queryItems: [URLQueryItem(name: "id", value: "eq.2")])
    let (response, _) = try await transport.send(HTTPRequest(method: .get, url: url), body: nil)

    #expect(response.status == .notFound)
  }

  @Test
  func stubKeepsTheResponseHeadersItIsGiven() async throws {
    let transport = RecordingTransport()
    transport.stub(
      .get, baseURL, data: Data("hi".utf8), headers: [.contentType: "text/plain"])

    let (response, _) = try await transport.send(HTTPRequest(method: .get, url: baseURL), body: nil)

    #expect(response.headerFields[.contentType] == "text/plain")
  }

  @Test
  func stubSendsNoContentTypeForABodyThatIsNotJSON() async throws {
    let transport = RecordingTransport()
    transport.stub(.get, baseURL, data: Data("relay failed".utf8))

    let (response, _) = try await transport.send(HTTPRequest(method: .get, url: baseURL), body: nil)

    #expect(response.headerFields[.contentType] == nil)
  }

  #if !os(Linux) && !os(Android)
    @Test
    func mismatchedRequestSnapshotFailsTheSendingTest() async throws {
      let transport = RecordingTransport()
      transport.stub(.get, baseURL) {
        "a curl command this request cannot possibly produce"
      }

      await withKnownIssue("the snapshot is deliberately wrong, so comparing it must report") {
        _ = try await transport.send(HTTPRequest(method: .get, url: baseURL), body: nil)
      }
    }
  #endif
}
