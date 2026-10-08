//
//  RealtimeURL.swift
//  Realtime
//
//  Created by Guilherme Souza on 08/10/26.
//

package import Foundation

/// Builds the URLs the Realtime client talks to.
package enum RealtimeURL {
  /// The WebSocket endpoint for `baseURL`: `http(s)` becomes `ws(s)`, then `apikey`, the
  /// protocol version and an optional `log_level` join the query and `/websocket` joins the path.
  package static func webSocket(baseURL: URL, apikey: String?, logLevel: String?) -> URL {
    guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
      return baseURL
    }

    if components.scheme == "https" {
      components.scheme = "wss"
    } else if components.scheme == "http" {
      components.scheme = "ws"
    }

    var queryItems = components.queryItems ?? []

    if let apikey {
      queryItems.append(URLQueryItem(name: "apikey", value: apikey))
    }

    queryItems.append(URLQueryItem(name: "vsn", value: "2.0.0"))

    if let logLevel {
      queryItems.append(URLQueryItem(name: "log_level", value: logLevel))
    }

    components.queryItems = queryItems

    components.path.append("/websocket")
    components.path = components.path.replacingOccurrences(of: "//", with: "/")

    return components.url ?? baseURL
  }

  /// Builds the REST broadcast URL for a single event: `.../api/broadcast/{topic}/events/{event}`.
  ///
  /// Topic and event are percent-encoded as individual path segments (so values containing
  /// `/` don't introduce extra path components), and a private channel adds `?private=true`.
  package static func broadcast(baseURL: URL, topic: String, event: String, isPrivate: Bool) -> URL
  {
    guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
      return baseURL
    }

    var path = components.percentEncodedPath
    if path.hasSuffix("/") { path.removeLast() }
    path += "/api/broadcast/\(encodeSegment(topic))/events/\(encodeSegment(event))"
    components.percentEncodedPath = path

    if isPrivate {
      components.queryItems = [URLQueryItem(name: "private", value: "true")]
    }

    return components.url ?? baseURL
  }

  /// Restricted to RFC 3986 "unreserved" characters so values containing `/`, `:`, or other
  /// reserved characters are always escaped rather than read as extra path structure.
  private static func encodeSegment(_ value: String) -> String {
    var allowed = CharacterSet.alphanumerics
    allowed.insert(charactersIn: "-._~")
    return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
  }
}
