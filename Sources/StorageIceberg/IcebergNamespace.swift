//
//  IcebergNamespace.swift
//  StorageIceberg
//
//  Created by Guilherme Souza on 25/11/26.
//

import HTTPTypes

/// A namespace in an ``IcebergCatalog``: a named group of tables with string properties.
///
/// - Warning: Experimental. See ``IcebergCatalog``.
@_spi(Experimental)
public struct IcebergNamespace: Hashable, Sendable {
  /// The namespace name.
  public var name: String

  /// The namespace properties, such as `owner`.
  public var properties: [String: String]

  /// Creates an ``IcebergNamespace``.
  public init(name: String, properties: [String: String]) {
    self.name = name
    self.properties = properties
  }
}

extension IcebergCatalog {
  /// Creates a namespace, or updates it when it already exists.
  ///
  /// Supabase Storage does not reject a name that is in use. It merges `properties` into the
  /// properties of the existing namespace and returns the result. At the namespace limit of the
  /// project, the catalog refuses the call with code `IcebergMaximumResourceLimit`, even for a
  /// name that exists.
  ///
  /// - Warning: Experimental. See ``IcebergCatalog``.
  ///
  /// - Parameters:
  ///   - name: The namespace name.
  ///   - properties: The properties to set on the namespace. Defaults to none.
  /// - Returns: The namespace, with the properties the catalog stored.
  /// - Throws: `StorageError` when the catalog rejects the request.
  @_spi(Experimental)
  @discardableResult
  public func createNamespace(_ name: String, properties: [String: String] = [:]) async throws
    -> IcebergNamespace
  {
    let response: NamespaceResponse = try await send(
      .post, path: ["namespaces"],
      body: CreateNamespaceRequest(namespace: name, properties: properties))
    return response.namespace
  }

  /// Lists the namespaces in the catalog.
  ///
  /// - Warning: Experimental. See ``IcebergCatalog``.
  ///
  /// - Returns: The namespace names.
  /// - Throws: `StorageError` when the catalog rejects the request.
  @_spi(Experimental)
  public func listNamespaces() async throws -> [String] {
    let response: ListNamespacesResponse = try await send(.get, path: ["namespaces"])
    return (response.namespaces ?? []).map(Self.name(of:))
  }

  /// Returns the properties of a namespace.
  ///
  /// - Warning: Experimental. See ``IcebergCatalog``.
  ///
  /// - Parameter name: The namespace name.
  /// - Returns: The namespace properties; empty when it has none.
  /// - Throws: `StorageError` when the catalog rejects the request, e.g. with code
  ///   `NoSuchNamespaceException` when the namespace does not exist.
  @_spi(Experimental)
  public func namespaceProperties(_ name: String) async throws -> [String: String] {
    let response: NamespaceResponse = try await send(.get, path: ["namespaces", name])
    return response.namespace.properties
  }

  /// Checks whether a namespace exists.
  ///
  /// - Warning: Experimental. See ``IcebergCatalog``.
  ///
  /// - Parameter name: The namespace name.
  /// - Returns: `true` when the namespace exists, `false` when the catalog answers 404. The
  ///   catalog also answers 404 when the bucket does not exist or the project has no Iceberg
  ///   catalog, and the answer has no body, so these cases also return `false`.
  /// - Throws: `StorageError` when the catalog rejects the request for another reason.
  @_spi(Experimental)
  public func namespaceExists(_ name: String) async throws -> Bool {
    try await exists(path: ["namespaces", name])
  }

  /// Deletes a namespace.
  ///
  /// - Warning: Experimental. See ``IcebergCatalog``.
  ///
  /// - Parameter name: The namespace name.
  /// - Throws: `StorageError` when the catalog rejects the request, e.g. with code
  ///   `IcebergResourceNotEmpty` when the namespace still holds tables.
  @_spi(Experimental)
  public func deleteNamespace(_ name: String) async throws {
    try await sendIgnoringBody(.delete, path: ["namespaces", name])
  }

  /// The name of a namespace sent as an array of levels.
  static func name(of levels: [String]) -> String {
    levels.joined(separator: ".")
  }
}

private struct CreateNamespaceRequest: Encodable {
  let namespace: String
  let properties: [String: String]
}

private struct NamespaceResponse: Decodable {
  let namespace: IcebergNamespace

  private enum CodingKeys: String, CodingKey {
    case namespace, properties
  }

  init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    namespace = IcebergNamespace(
      name: IcebergCatalog.name(of: try container.decode([String].self, forKey: .namespace)),
      properties: try container.decodeIfPresent([String: String].self, forKey: .properties) ?? [:])
  }
}

private struct ListNamespacesResponse: Decodable {
  let namespaces: [[String]]?
}
