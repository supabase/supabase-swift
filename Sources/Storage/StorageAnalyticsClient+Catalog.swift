//
//  StorageAnalyticsClient+Catalog.swift
//  Storage
//
//  Created by Guilherme Souza on 25/11/26.
//

package import Foundation
package import HTTPTypes

extension StorageAnalyticsClient {
  /// Sends `method` to `iceberg/v1/<segments, each encoded with ObjectKey.encode>`,
  /// with `Content-Type: application/json` when `body` is set. Returns the 2xx body.
  package func sendCatalogRequest(
    _ method: HTTPRequest.Method, path segments: [String],
    query: [URLQueryItem] = [], body: Data? = nil
  ) async throws -> Data {
    let path = (["iceberg", "v1"] + segments.map(ObjectKey.encode)).joined(separator: "/")
    var head = HTTPRequest(method: method, url: api.requests.url(path, query: query))
    if body != nil {
      head.headerFields[.contentType] = "application/json"
    }
    return try await api.execute(head, body: body)
  }
}
