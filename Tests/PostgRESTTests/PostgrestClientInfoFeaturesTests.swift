//
//  PostgrestClientInfoFeaturesTests.swift
//  Supabase
//
//  Created by Guilherme Souza on 27/10/26.
//

import Foundation
import Testing

@_spi(Experimental) @testable import PostgREST

@Suite
struct PostgrestClientInfoFeaturesTests {
  typealias Todo = PostgrestMutationTests.Todo

  static let clientInfo = "supabase-swift/3.0.0; platform=iOS; runtime=swift; runtime-version=6.2"
  static let typedClientInfo = clientInfo + "; features=typed-api"

  private func capture() -> QueryCapture {
    QueryCapture(headers: ["X-Client-Info": Self.clientInfo])
  }

  @Test
  func typedSelectSendsTheTypedAPIFeature() async throws {
    let capture = capture()
    _ = try await capture.client.from(Todo.self).select().execute()
    #expect(capture.header("X-Client-Info") == Self.typedClientInfo)
  }

  @Test
  func typedRawQuerySendsTheTypedAPIFeature() async throws {
    let capture = capture()
    _ = try await capture.client.from(Todo.self).select().csv().execute()
    #expect(capture.header("X-Client-Info") == Self.typedClientInfo)
  }

  @Test
  func typedInsertSendsTheTypedAPIFeature() async throws {
    let capture = capture()
    _ = try await capture.client.from(Todo.self).insert(Todo.Draft(task: "buy milk")).execute()
    #expect(capture.header("X-Client-Info") == Self.typedClientInfo)
  }

  @Test
  func typedUpsertSendsTheTypedAPIFeature() async throws {
    let capture = capture()
    _ = try await capture.client.from(Todo.self).upsert(Todo.Draft(task: "buy milk")).execute()
    #expect(capture.header("X-Client-Info") == Self.typedClientInfo)
  }

  @Test
  func typedUpdateSendsTheTypedAPIFeature() async throws {
    let capture = capture()
    _ = try await capture.client.from(Todo.self)
      .update { $0.task = "done" }.where { $0.id.eq(1) }.execute()
    #expect(capture.header("X-Client-Info") == Self.typedClientInfo)
  }

  @Test
  func typedDeleteSendsTheTypedAPIFeature() async throws {
    let capture = capture()
    _ = try await capture.client.from(Todo.self).delete().where { $0.id.eq(1) }.execute()
    #expect(capture.header("X-Client-Info") == Self.typedClientInfo)
  }

  @Test
  func untypedRequestsSendNoFeatures() async throws {
    let capture = capture()
    try await capture.client.from("todos").select().execute()
    #expect(capture.header("X-Client-Info") == Self.clientInfo)

    try await capture.client.rpc("search_todos").execute()
    #expect(capture.header("X-Client-Info") == Self.clientInfo)
  }

  @Test
  func aClientMixingBothAPIsSendsTheFeatureOnlyOnTypedRequests() async throws {
    let capture = capture()
    var sent: [String?] = []

    _ = try await capture.client.from(Todo.self).select().execute()
    sent.append(capture.header("X-Client-Info"))
    try await capture.client.from("todos").select().execute()
    sent.append(capture.header("X-Client-Info"))
    _ = try await capture.client.from(Todo.self).delete().all().execute()
    sent.append(capture.header("X-Client-Info"))

    #expect(sent == [Self.typedClientInfo, Self.clientInfo, Self.typedClientInfo])
  }

  @Test
  func aRequestWithoutAClientInfoHeaderGetsNone() {
    var request = _PostgrestRequest(relation: "todos")
    request.clientInfoFeatures = [.typedAPI]
    let configuration = PostgrestClient.Configuration(
      url: URL(string: "https://example.supabase.co")!)
    #expect(request.httpRequest(for: configuration).headerFields[.xClientInfo] == nil)
  }
}
