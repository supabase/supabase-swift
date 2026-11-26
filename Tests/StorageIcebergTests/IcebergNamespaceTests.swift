//
//  IcebergNamespaceTests.swift
//  StorageIceberg
//
//  Created by Guilherme Souza on 25/11/26.
//

import ConcurrencyExtras
import Foundation
import HTTPTypes
import Helpers
import TestHelpers
import Testing

@_spi(Experimental) import Storage
@_spi(Experimental) import StorageIceberg

@Suite
struct IcebergNamespaceTests {
  @Test
  func createNamespacePostsTheNameAndProperties() async throws {
    let sent = LockIsolated<[Sent]>([])
    let catalog = try makeCatalog(
      sent: sent, response: #"{"namespace":["sales"],"properties":{"owner":"data"}}"#)

    let namespace = try await catalog.createNamespace("sales", properties: ["owner": "data"])

    #expect(namespace == IcebergNamespace(name: "sales", properties: ["owner": "data"]))
    let request = try #require(sent.value.first)
    #expect(request.request.method == .post)
    #expect(request.request.path == "/storage/v1/iceberg/v1/events/namespaces")
    #expect(request.request.headerFields[.contentType] == "application/json")
    #expect(
      try jsonEqual(request.body, #"{"namespace":"sales","properties":{"owner":"data"}}"#))
  }

  @Test
  func listNamespacesReturnsTheNames() async throws {
    let sent = LockIsolated<[Sent]>([])
    let catalog = try makeCatalog(sent: sent, response: #"{"namespaces":[["a"],["b"]]}"#)

    #expect(try await catalog.listNamespaces() == ["a", "b"])
    #expect(sent.value.map(\.request.method) == [.get])
    #expect(sent.value.map(\.request.path) == ["/storage/v1/iceberg/v1/events/namespaces"])

    let empty = try makeCatalog(response: "{}")
    #expect(try await empty.listNamespaces() == [])
  }

  @Test
  func namespacePropertiesDecodesMissingPropertiesAsEmpty() async throws {
    let sent = LockIsolated<[Sent]>([])
    let catalog = try makeCatalog(sent: sent, response: #"{"namespace":["a"]}"#)

    #expect(try await catalog.namespaceProperties("a") == [:])
    #expect(sent.value.map(\.request.method) == [.get])
    #expect(sent.value.map(\.request.path) == ["/storage/v1/iceberg/v1/events/namespaces/a"])
  }

  @Test
  func namespaceExistsIsTrueOn204AndFalseOn404() async throws {
    let sent = LockIsolated<[Sent]>([])
    let present = try makeCatalog(sent: sent, status: .noContent, response: "")
    let missing = try makeCatalog(status: .notFound, response: "")

    #expect(try await present.namespaceExists("a") == true)
    #expect(try await missing.namespaceExists("a") == false)
    #expect(sent.value.map(\.request.method) == [.head])
    #expect(sent.value.map(\.request.path) == ["/storage/v1/iceberg/v1/events/namespaces/a"])
  }

  @Test
  func namespaceExistsThrowsOnForbidden() async throws {
    let catalog = try makeCatalog(
      status: .forbidden,
      response: #"""
        {"error":{"message":"Forbidden","type":"ForbiddenException","code":403}}
        """#)

    let error = try await #require(throws: StorageError.self) {
      try await catalog.namespaceExists("a")
    }
    #expect(error.code?.rawValue == "ForbiddenException")
  }

  @Test
  func deleteNamespaceSendsDelete() async throws {
    let sent = LockIsolated<[Sent]>([])
    let catalog = try makeCatalog(sent: sent, status: .noContent, response: "")

    try await catalog.deleteNamespace("a")

    #expect(sent.value.map(\.request.method) == [.delete])
    #expect(sent.value.map(\.request.path) == ["/storage/v1/iceberg/v1/events/namespaces/a"])
    #expect(sent.value.first?.request.headerFields[.contentType] == nil)
  }

  @Test
  func namesStayOnePathSegment() async throws {
    let sent = LockIsolated<[Sent]>([])
    let catalog = try makeCatalog(sent: sent, status: .noContent, response: "")
    let spaced = try makeCatalog(bucket: "my bucket", sent: sent, status: .noContent, response: "")

    try await catalog.deleteNamespace("a b/c")
    try await catalog.deleteNamespace("..")
    try await spaced.deleteNamespace("a")

    #expect(
      sent.value.map(\.request.path) == [
        "/storage/v1/iceberg/v1/events/namespaces/a%20b%2Fc",
        "/storage/v1/iceberg/v1/events/namespaces/%2E%2E",
        "/storage/v1/iceberg/v1/my%20bucket/namespaces/a",
      ])
  }

  @Test
  func aMissingNamespaceErrorKeepsItsType() async throws {
    let catalog = try makeCatalog(
      status: .notFound,
      response: #"""
        {"error":{"message":"Namespace does not exist","type":"NoSuchNamespaceException","code":404}}
        """#)

    let error = try await #require(throws: StorageError.self) {
      try await catalog.namespaceProperties("missing")
    }
    #expect(error.code?.rawValue == "NoSuchNamespaceException")
    #expect(error.message == "Namespace does not exist")
    #expect(error.isNotFound)
  }

  @Test
  func aNonEmptyNamespaceErrorKeepsTheMessageAndStatus() async throws {
    let catalog = try makeCatalog(
      status: .badRequest,
      response: #"""
        {"error":{"message":"The resource namespace: ns1 is not empty","type":"IcebergResourceNotEmpty","code":400}}
        """#)

    let error = try await #require(throws: StorageError.self) {
      try await catalog.deleteNamespace("ns1")
    }
    #expect(error.kind == .server)
    #expect(error.message == "The resource namespace: ns1 is not empty")
    #expect(error.code == .icebergResourceNotEmpty)
    #expect(error.serverError?.statusCode == 400)
    #expect(error.response?.status == .badRequest)
  }

  @Test
  func cancellationSurfacesAsCancellationError() async throws {
    let started = AsyncStream<Void>.makeStream()
    let catalog = try makeCatalog(
      transport: ClosureTransport { _, _ in
        started.continuation.yield()
        try await Task.sleep(for: .seconds(60))
        return (HTTPResponse(status: .ok), nil)
      })

    let task = Task { try await catalog.listNamespaces() }
    for await _ in started.stream { break }
    task.cancel()

    await #expect(throws: CancellationError.self) { try await task.value }
  }
}
