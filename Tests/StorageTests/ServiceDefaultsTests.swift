import Foundation
import HTTPTypes
import Testing

@testable import Storage

/// Storage owns the defaults of `x-upsert` and of the list paging and sort, so a `nil` option
/// leaves the field out of the request.
@Suite
struct ServiceDefaultsTests {
  let requests = try! StorageRequests(url: URL(string: "http://localhost:54321/storage/v1")!)
  let key = try! ObjectKey("folder/a.txt")

  private func body(_ request: StorageRequest) async throws -> String {
    let data = try await Data(collecting: try #require(request.body), upTo: .max)
    return String(decoding: data, as: UTF8.self)
  }

  private func tusMetadataKeys(_ request: StorageRequest) throws -> [String] {
    let header = try #require(request.head.headerFields[.uploadMetadata])
    return header.split(separator: ",").map { String($0.split(separator: " ")[0]) }
  }

  @Test
  func uploadWithDefaultOptionsLeavesUpsertOut() throws {
    let request = try requests.upload(
      method: .post, bucket: "bucket", key: key, body: HTTPBody(Data()), options: UploadOptions())

    #expect(request.head.headerFields[.xUpsert] == nil)
  }

  @Test(arguments: [true, false])
  func uploadSendsAnExplicitUpsert(_ upsert: Bool) throws {
    let request = try requests.upload(
      method: .post, bucket: "bucket", key: key, body: HTTPBody(Data()),
      options: UploadOptions(upsert: upsert))

    #expect(request.head.headerFields[.xUpsert] == "\(upsert)")
  }

  @Test
  func tusCreateWithDefaultOptionsLeavesUpsertOut() throws {
    let request = try requests.tusCreate(
      bucket: "bucket", key: key, length: 1, options: UploadOptions(), firstChunk: nil)

    #expect(request.head.headerFields[.xUpsert] == nil)
  }

  @Test(arguments: [true, false])
  func tusCreateSendsAnExplicitUpsert(_ upsert: Bool) throws {
    let request = try requests.tusCreate(
      bucket: "bucket", key: key, length: 1, options: UploadOptions(upsert: upsert),
      firstChunk: nil)

    #expect(request.head.headerFields[.xUpsert] == "\(upsert)")
  }

  @Test
  func cacheControlKeepsTheSDKDefault() throws {
    let upload = try requests.upload(
      method: .post, bucket: "bucket", key: key, body: HTTPBody(Data()), options: UploadOptions())
    let tus = try requests.tusCreate(
      bucket: "bucket", key: key, length: 1, options: UploadOptions(), firstChunk: nil)

    #expect(upload.head.headerFields[.cacheControl] == "max-age=3600")
    #expect(try tusMetadataKeys(tus).contains("cacheControl"))
  }

  @Test
  func listWithDefaultOptionsSendsOnlyThePrefix() async throws {
    let request = try requests.list(bucket: "bucket", prefix: key, options: ListOptions())

    #expect(try await body(request) == #"{"prefix":"folder\/a.txt"}"#)
  }

  @Test
  func listSendsExplicitPaging() async throws {
    let request = try requests.list(
      bucket: "bucket", prefix: key, options: ListOptions(limit: 100, offset: 0))

    #expect(try await body(request) == #"{"limit":100,"offset":0,"prefix":"folder\/a.txt"}"#)
  }

  @Test
  func listWithOnlyAColumnLeavesTheOrderOut() async throws {
    let request = try requests.list(
      bucket: "bucket", prefix: key, options: ListOptions(sortBy: .updatedAt))

    #expect(
      try await body(request) == #"{"prefix":"folder\/a.txt","sortBy":{"column":"updated_at"}}"#)
  }

  @Test
  func listWithOnlyAnOrderSendsTheNameColumn() async throws {
    let request = try requests.list(
      bucket: "bucket", prefix: key, options: ListOptions(order: .descending))

    #expect(
      try await body(request)
        == #"{"prefix":"folder\/a.txt","sortBy":{"column":"name","order":"desc"}}"#)
  }

  @Test
  func listSendsBothSortParts() async throws {
    let request = try requests.list(
      bucket: "bucket", prefix: key, options: ListOptions(sortBy: .createdAt, order: .ascending))

    #expect(
      try await body(request)
        == #"{"prefix":"folder\/a.txt","sortBy":{"column":"created_at","order":"asc"}}"#)
  }
}
