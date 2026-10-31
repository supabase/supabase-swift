//
//  MailCatcher.swift
//
//
//  Reads mail from the local stack's Mailpit server.
//

import Foundation

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

struct MailCatcher {
  struct NoLinkError: Error, CustomStringConvertible {
    let email: String
    var description: String { "No email with a /verify link arrived for \(email)" }
  }

  struct UnexpectedStatusError: Error, CustomStringConvertible {
    let url: URL
    let status: Int?
    var description: String { "GET \(url) returned status \(status.map(String.init) ?? "none")" }
  }

  private func get(_ url: URL) async throws -> Data {
    let (data, response) = try await URLSession.shared.data(from: url)
    let status = (response as? HTTPURLResponse)?.statusCode
    guard status == 200 else { throw UnexpectedStatusError(url: url, status: status) }
    return data
  }

  private let baseURL = URL(string: "http://127.0.0.1:54324")!

  func latestLink(to email: String, timeout: Duration = .seconds(10)) async throws -> URL {
    let deadline = ContinuousClock.now + timeout
    while true {
      if let link = try await verifyLink(to: email) {
        return link
      }
      guard ContinuousClock.now < deadline else {
        throw NoLinkError(email: email)
      }
      try await Task.sleep(for: .milliseconds(250))
    }
  }

  private func verifyLink(to email: String) async throws -> URL? {
    var search = URLComponents(
      url: baseURL.appendingPathComponent("api/v1/search"),
      resolvingAgainstBaseURL: false
    )!
    search.queryItems = [URLQueryItem(name: "query", value: "to:\(email)")]

    let searchData = try await get(search.url!)
    let found = try JSONDecoder().decode(SearchResponse.self, from: searchData)
    guard let id = found.messages.first?.ID else { return nil }

    let messageData = try await get(baseURL.appendingPathComponent("api/v1/message/\(id)"))
    let message = try JSONDecoder().decode(Message.self, from: messageData)

    let pattern = #"href\s*=\s*"([^"]*\/verify[^"]*)""#
    let regex = try NSRegularExpression(pattern: pattern)
    let html = message.HTML
    guard
      let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
      let range = Range(match.range(at: 1), in: html)
    else { return nil }

    return URL(string: String(html[range]).replacingOccurrences(of: "&amp;", with: "&"))
  }

  private struct SearchResponse: Decodable {
    struct Summary: Decodable { let ID: String }
    let messages: [Summary]
  }

  private struct Message: Decodable {
    let HTML: String
  }
}

private final class NoRedirectDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
  func urlSession(
    _ session: URLSession,
    task: URLSessionTask,
    willPerformHTTPRedirection response: HTTPURLResponse,
    newRequest request: URLRequest,
    completionHandler: @escaping (URLRequest?) -> Void
  ) {
    completionHandler(nil)
  }
}

struct MissingLocationError: Error, CustomStringConvertible {
  let url: URL
  let status: Int?
  var description: String {
    "GET \(url) returned status \(status.map(String.init) ?? "none") without a Location header"
  }
}

/// Sends a GET request without following redirects and returns the `Location` header.
func redirectLocation(of url: URL) async throws -> URL {
  let session = URLSession(
    configuration: .ephemeral,
    delegate: NoRedirectDelegate(),
    delegateQueue: nil
  )
  defer { session.finishTasksAndInvalidate() }

  let (_, response) = try await session.data(from: url)
  let http = response as? HTTPURLResponse
  guard
    let location = http?.value(forHTTPHeaderField: "Location"),
    let result = URL(string: location)
  else { throw MissingLocationError(url: url, status: http?.statusCode) }
  return result
}
