import ConcurrencyExtras
import XCTest

@testable import Storage

final class ResumableClientStoreTests: XCTestCase {
  var storage: SupabaseStorageClient!

  override func setUp() {
    super.setUp()

    storage = SupabaseStorageClient.test(
      supabaseURL: "http://localhost:54321/storage/v1",
      apiKey: "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0"
    )
  }

  func testInitializeStore() async throws {
    let api = storage.from("bucket").resumable
    let store = api.clientStore
    let clients = await store.clients.value
    XCTAssertEqual(clients.values.count, 0)
  }

  func testCreateClient() async throws {
    let api = storage.from("bucket").resumable
    let store = api.clientStore
    let client = try await store.getOrCreateClient(for: "bucket")
    let clients = await store.clients.value
    XCTAssertEqual(clients.values.count, 1)

    let clientFromStore = await store.clients.value["bucket"]
    XCTAssertNotNil(clientFromStore)
    XCTAssertEqual(clientFromStore!.bucketId, client.bucketId)
  }

  func testRemoveClient() async throws {
    let api = storage.from("bucket").resumable
    let store = api.clientStore
    _ = try await store.getOrCreateClient(for: "bucket")
    var clients = await store.clients.value
    XCTAssertEqual(clients.values.count, 1)
    await store.removeClient(for: "bucket")
    clients = await store.clients.value
    XCTAssertEqual(clients.values.count, 0)
  }

  func testRemoveAllClients() async throws {
    let api = storage.from("bucket").resumable
    let store = api.clientStore
    _ = try await store.getOrCreateClient(for: "bucket")
    _ = try await store.getOrCreateClient(for: "bucket1")
    var clients = await store.clients.value
    XCTAssertEqual(clients.values.count, 2)
    await store.removeAllClients()
    clients = await store.clients.value
    XCTAssertEqual(clients.values.count, 0)
  }
}
