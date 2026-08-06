//
//  AnalyticsBucketClient.swift
//  Storage
//
//  Created by Guilherme Souza on 06/08/26.
//

import Foundation
import HTTPTypes

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

/// A client scoped to a single analytics bucket, for managing its Iceberg namespaces and tables.
///
/// Obtain an instance via ``AnalyticsClient/from(_:)``:
///
/// ```swift
/// let bucket = client.storage.analytics.from("events")
/// try await bucket.createNamespace("default")
/// let namespace = bucket.namespace("default")
/// ```
///
/// - Warning: Analytics buckets are a public alpha feature of Supabase Storage and this API is
///   experimental — it may change in a breaking way, or be unavailable on your project, until it
///   reaches general availability. Opt in with `@_spi(Experimental) import Supabase`.
///
/// ## Topics
///
/// ### Managing namespaces
///
/// - ``createNamespace(_:properties:)``
/// - ``getNamespace(_:)``
/// - ``listNamespaces(parent:pageSize:pageToken:)``
/// - ``namespaceExists(_:)``
/// - ``deleteNamespace(_:)``
///
/// ### Accessing tables
///
/// - ``namespace(_:)``
@_spi(Experimental)
public struct AnalyticsBucketClient: Sendable {
  /// The name of the analytics bucket this client operates on.
  public let bucketName: String

  private let api: StorageApi

  init(bucketName: String, api: StorageApi) {
    self.bucketName = bucketName
    self.api = api
  }

  /// Creates a new namespace in this bucket.
  ///
  /// ```swift
  /// try await bucket.createNamespace("default")
  /// ```
  ///
  /// - Warning: Experimental. See ``AnalyticsClient``.
  ///
  /// - Parameters:
  ///   - name: The name of the namespace to create.
  ///   - properties: Arbitrary key-value properties to store with the namespace.
  /// - Returns: The created ``IcebergNamespace``.
  /// - Throws: ``StorageError`` when the API rejects the request.
  public func createNamespace(
    _ name: String,
    properties: [String: String]? = nil
  ) async throws -> IcebergNamespace {
    try await api.execute(
      HTTPRequest(
        url: api.configuration.url.appendingPathComponent("iceberg/v1/\(bucketName)/namespaces"),
        method: .post,
        body: JSONEncoder.unconfiguredEncoder.encode(
          CreateNamespaceBody(namespace: name, properties: properties)
        )
      )
    )
    .decoded(decoder: .supabase())
  }

  /// Retrieves the properties of an existing namespace.
  ///
  /// ```swift
  /// let namespace = try await bucket.getNamespace("default")
  /// ```
  ///
  /// - Warning: Experimental. See ``AnalyticsClient``.
  ///
  /// - Parameter name: The name of the namespace to retrieve.
  /// - Returns: The matching ``IcebergNamespace``.
  /// - Throws: ``StorageError`` when the API rejects the request.
  public func getNamespace(_ name: String) async throws -> IcebergNamespace {
    try await api.execute(
      HTTPRequest(
        url: api.configuration.url.appendingPathComponent(
          "iceberg/v1/\(bucketName)/namespaces/\(name)"),
        method: .get
      )
    )
    .decoded(decoder: .supabase())
  }

  /// Lists the namespaces in this bucket.
  ///
  /// Results are paginated: pass the ``ListIcebergNamespacesResponse/nextPageToken`` of a previous
  /// response as `pageToken` to fetch the following page.
  ///
  /// ```swift
  /// let page = try await bucket.listNamespaces()
  /// for namespace in page.namespaces {
  ///   print(namespace)
  /// }
  /// ```
  ///
  /// - Warning: Experimental. See ``AnalyticsClient``.
  ///
  /// - Parameters:
  ///   - parent: Returns only namespaces nested under this parent namespace.
  ///   - pageSize: The maximum number of namespaces to return in this page.
  ///   - pageToken: The pagination token from a previous response.
  /// - Returns: A page of namespace names, plus the token for the next page when more results
  ///   exist.
  /// - Throws: ``StorageError`` when the API rejects the request.
  public func listNamespaces(
    parent: String? = nil,
    pageSize: Int? = nil,
    pageToken: String? = nil
  ) async throws -> ListIcebergNamespacesResponse {
    var query: [URLQueryItem] = []
    if let parent { query.append(URLQueryItem(name: "parent", value: parent)) }
    if let pageSize { query.append(URLQueryItem(name: "pageSize", value: String(pageSize))) }
    if let pageToken { query.append(URLQueryItem(name: "pageToken", value: pageToken)) }

    let response: ListNamespacesResponseBody = try await api.execute(
      HTTPRequest(
        url: api.configuration.url.appendingPathComponent("iceberg/v1/\(bucketName)/namespaces"),
        method: .get,
        query: query
      )
    )
    .decoded(decoder: .supabase())
    return ListIcebergNamespacesResponse(
      namespaces: response.namespaces.compactMap(\.first),
      nextPageToken: response.nextPageToken
    )
  }

  /// Checks whether a namespace exists in this bucket.
  ///
  /// ```swift
  /// if try await bucket.namespaceExists("default") {
  ///   // ...
  /// }
  /// ```
  ///
  /// - Warning: Experimental. See ``AnalyticsClient``.
  ///
  /// - Parameter name: The name of the namespace to check.
  /// - Returns: `true` if the namespace exists, `false` otherwise.
  /// - Throws: ``StorageError`` for any failure other than the namespace not existing.
  public func namespaceExists(_ name: String) async throws -> Bool {
    do {
      try await api.execute(
        HTTPRequest(
          url: api.configuration.url.appendingPathComponent(
            "iceberg/v1/\(bucketName)/namespaces/\(name)"),
          method: .head
        )
      )
      return true
    } catch let error as StorageError {
      if let statusCode = error.statusCode.flatMap(Int.init), [400, 404].contains(statusCode) {
        return false
      }
      throw error
    }
  }

  /// Deletes a namespace.
  ///
  /// > Important: A namespace cannot be deleted while it contains tables. Drop all tables first.
  ///
  /// ```swift
  /// try await bucket.deleteNamespace("default")
  /// ```
  ///
  /// - Warning: Experimental. See ``AnalyticsClient``.
  ///
  /// - Parameter name: The name of the namespace to delete.
  /// - Throws: ``StorageError`` when the API rejects the request.
  public func deleteNamespace(_ name: String) async throws {
    try await api.execute(
      HTTPRequest(
        url: api.configuration.url.appendingPathComponent(
          "iceberg/v1/\(bucketName)/namespaces/\(name)"),
        method: .delete
      )
    )
  }

  /// Returns a client scoped to the given namespace, for managing its Iceberg tables.
  ///
  /// ```swift
  /// let namespace = client.storage.analytics.from("events").namespace("default")
  /// try await namespace.listTables()
  /// ```
  ///
  /// - Warning: Experimental. See ``AnalyticsClient``.
  ///
  /// - Parameter name: The name of the namespace.
  /// - Returns: An ``IcebergNamespaceClient`` configured for the given namespace.
  public func namespace(_ name: String) -> IcebergNamespaceClient {
    IcebergNamespaceClient(
      bucketName: bucketName,
      namespaceName: name,
      api: api
    )
  }
}

private struct CreateNamespaceBody: Encodable {
  var namespace: String
  var properties: [String: String]?
}

private struct ListNamespacesResponseBody: Decodable {
  var namespaces: [[String]]
  var nextPageToken: String?

  private enum CodingKeys: String, CodingKey {
    case namespaces
    case nextPageToken = "next-page-token"
  }
}

/// An Iceberg namespace, as returned by ``AnalyticsBucketClient``.
///
/// - Warning: Experimental. See ``AnalyticsClient``.
@_spi(Experimental)
public struct IcebergNamespace: Sendable, Hashable {
  /// The name of the namespace.
  public var name: String

  /// Arbitrary key-value properties stored with the namespace.
  public var properties: [String: String]?
}

extension IcebergNamespace: Decodable {
  private enum CodingKeys: String, CodingKey {
    case namespace
    case properties
  }

  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let namespace = try container.decode([String].self, forKey: .namespace)
    name = namespace.first ?? ""
    properties = try container.decodeIfPresent([String: String].self, forKey: .properties)
  }
}

/// A page of namespace names, as returned by
/// ``AnalyticsBucketClient/listNamespaces(parent:pageSize:pageToken:)``.
///
/// - Warning: Experimental. See ``AnalyticsClient``.
@_spi(Experimental)
public struct ListIcebergNamespacesResponse: Sendable {
  /// The namespace names in this page.
  public var namespaces: [String]

  /// The pagination token to pass to fetch the next page, or `nil` when there are no more results.
  public var nextPageToken: String?
}
