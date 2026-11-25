//
//  IcebergCatalog.swift
//  StorageIceberg
//
//  Created by Guilherme Souza on 25/11/26.
//

@_spi(Experimental) public import Storage

extension StorageAnalyticsClient {
  /// Returns a client for the Iceberg REST catalog of an analytics bucket.
  ///
  /// - Warning: Experimental. See ``IcebergCatalog``.
  ///
  /// - Parameter bucket: The name of the analytics bucket.
  /// - Returns: The catalog client. It sends no request until you call one of its methods.
  @_spi(Experimental)
  public func catalog(bucket: String) -> IcebergCatalog {
    IcebergCatalog(analytics: self, bucket: bucket)
  }
}

/// A client for the Iceberg REST catalog of one analytics bucket.
///
/// Obtain an instance with ``Storage/StorageAnalyticsClient/catalog(bucket:)``:
///
/// ```swift
/// @_spi(Experimental) import StorageIceberg
///
/// let catalog = client.storage.analytics.catalog(bucket: "events")
/// try await catalog.createNamespace("sales")
/// let namespaces = try await catalog.listNamespaces()
/// ```
///
/// Every method needs the `secret` key and throws `StorageError` when the catalog rejects the
/// request. The catalog's own error type, such as `NoSuchNamespaceException`, is in the error's
/// `code`. A cancelled task throws `CancellationError`.
///
/// - Warning: Analytics buckets are a public alpha feature of Supabase Storage and this API is
///   experimental — it may change in a breaking way, or be unavailable on your project, until it
///   reaches general availability. Opt in with `@_spi(Experimental) import StorageIceberg`.
///
/// ## Topics
///
/// ### Managing namespaces
///
/// - ``createNamespace(_:properties:)``
/// - ``listNamespaces()``
/// - ``namespaceProperties(_:)``
/// - ``namespaceExists(_:)``
/// - ``deleteNamespace(_:)``
/// - ``IcebergNamespace``
@_spi(Experimental)
public struct IcebergCatalog: Sendable {
  let analytics: StorageAnalyticsClient

  /// The name of the analytics bucket that holds this catalog.
  ///
  /// - Warning: Experimental. See ``IcebergCatalog``.
  public let bucket: String
}
