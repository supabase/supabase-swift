//
//  SnapshotStrategy.swift
//  Supabase
//
//  Created by Guilherme Souza on 22/01/25.
//

@preconcurrency import InlineSnapshotTesting

#if !os(WASI)
  import Foundation

  #if canImport(FoundationNetworking)
    import FoundationNetworking
  #endif

  extension Snapshotting where Value == URLRequest, Format == String {
    /// A snapshot strategy for comparing requests based on a cURL representation.
    ///
    // ``` swift
    // assertSnapshot(of: request, as: .curl)
    // ```
    //
    // Records:
    //
    // ```
    // curl \
    //   --request POST \
    //   --header "Accept: text/html" \
    //   --data 'pricing[billing]=monthly&pricing[lane]=individual' \
    //   "https://www.pointfree.co/subscribe"
    // ```
    package static let _curl = SimplySnapshotting.lines.pullback { (request: URLRequest) in

      var components = ["curl"]

      // HTTP Method
      let httpMethod = request.httpMethod!
      switch httpMethod {
      case "GET": break
      case "HEAD": components.append("--head")
      default: components.append("--request \(httpMethod)")
      }

      // Headers
      if let headers = request.allHTTPHeaderFields {
        for field in headers.keys.sorted() where field != "Cookie" {
          let escapedValue = headers[field]!.replacingOccurrences(of: "\"", with: "\\\"")
          components.append("--header \"\(field): \(escapedValue)\"")
        }
      }

      // Body
      if let httpBodyData = request.bodyData,
        let httpBody = String(data: httpBodyData, encoding: .utf8)
      {
        var escapedBody = httpBody.replacingOccurrences(of: "\\\"", with: "\\\\\"")
        escapedBody = escapedBody.replacingOccurrences(of: "\"", with: "\\\"")

        components.append("--data \"\(escapedBody)\"")
      }

      // Cookies
      if let cookie = request.allHTTPHeaderFields?["Cookie"] {
        let escapedValue = cookie.replacingOccurrences(of: "\"", with: "\\\"")
        components.append("--cookie \"\(escapedValue)\"")
      }

      // URL
      components.append("\"\(request.url!.sortingQueryItems()!.absoluteString)\"")

      return components.joined(separator: " \\\n\t")
    }
  }

  extension URL {
    fileprivate func sortingQueryItems() -> URL? {
      var components = URLComponents(url: self, resolvingAgainstBaseURL: false)
      let sortedQueryItems = components?.queryItems?.sorted { $0.name < $1.name }
      components?.queryItems = sortedQueryItems

      return components?.url
    }
  }

  extension URLRequest {
    package var bodyData: Data? {
      httpBody ?? httpBodyStream.map { Data(reading: $0, withBufferSize: 1024) }
    }
  }

  extension Data {
    package init(reading stream: InputStream, withBufferSize bufferSize: UInt = 1024) {
      self.init()

      stream.open()
      defer { stream.close() }

      let bufferSize = Int(bufferSize)
      let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
      defer { buffer.deallocate() }

      while stream.hasBytesAvailable {
        let read = stream.read(buffer, maxLength: bufferSize)
        guard read > 0 else { return }
        self.append(buffer, count: read)
      }
    }
  }
#endif
