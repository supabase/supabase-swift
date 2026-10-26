import CustomDump
import Foundation
import Testing

@testable import Auth

@Suite
struct PendingFlowRecordTests {
  private let id = UUID(uuidString: "6C69F399-BE1B-467A-9C53-D3753ABDD2DF")!
  private let createdAt = Date(timeIntervalSince1970: 1_790_073_765)

  @Test
  func recordEncodesToItsStoredShape() throws {
    let record = PendingFlowRecord(
      id: id,
      verifier: "verifier",
      purpose: .recovery,
      redirectTo: URL(string: "myapp://reset-password"),
      createdAt: createdAt
    )

    let data = try record.encoded()

    expectNoDifference(
      String(decoding: data, as: UTF8.self),
      #"{"created_at":"2026-09-22T10:42:45Z","id":"6C69F399-BE1B-467A-9C53-D3753ABDD2DF","#
        + #""purpose":"recovery","redirect_to":"myapp:\/\/reset-password","verifier":"verifier"}"#
    )
    #expect(try PendingFlowRecord.decode(data) == record)
  }

  @Test
  func recordWithoutRedirectRoundTrips() throws {
    let record = PendingFlowRecord(
      id: id,
      verifier: "verifier",
      purpose: .signIn,
      redirectTo: nil,
      createdAt: createdAt
    )

    #expect(try PendingFlowRecord.decode(record.encoded()) == record)
  }

  @Test
  func recordWithAnUnknownPurposeFailsDecoding() {
    let data = Data(
      #"""
      {"created_at":"2026-09-22T10:42:45Z","id":"6C69F399-BE1B-467A-9C53-D3753ABDD2DF",
       "purpose":"teleport","verifier":"verifier"}
      """#.utf8
    )

    #expect(throws: DecodingError.self) {
      try PendingFlowRecord.decode(data)
    }
  }

  @Test
  func keysAreScopedToTheStorageKey() {
    #expect(
      PendingFlowRecord.key(id: id, storageKey: "sb-ref-auth-token")
        == "sb-ref-auth-token-flow-6c69f399-be1b-467a-9c53-d3753abdd2df"
    )
    #expect(PendingFlowIndex.key(storageKey: "sb-ref-auth-token") == "sb-ref-auth-token-flows")
  }

  @Test
  func aFlowExpiresAfterOneHour() {
    #expect(!PendingFlowRecord.isExpired(createdAt: createdAt, at: createdAt + 3599))
    #expect(PendingFlowRecord.isExpired(createdAt: createdAt, at: createdAt + 3600))
  }

  @Test
  func indexKeepsTheFiveNewestFlows() {
    var index = PendingFlowIndex()
    let ids = (0..<7).map { _ in UUID() }

    var dropped: [UUID] = []
    for (offset, id) in ids.enumerated() {
      let entry = PendingFlowIndex.Entry(id: id, createdAt: createdAt + Double(offset))
      dropped += index.insert(entry, now: createdAt + Double(offset))
    }

    #expect(dropped == Array(ids.prefix(2)))
    #expect(index.flows.map(\.id) == Array(ids.suffix(5)))
  }

  @Test
  func indexDropsExpiredFlowsOnInsert() {
    var index = PendingFlowIndex()
    let old = UUID()
    let recent = UUID()
    _ = index.insert(.init(id: old, createdAt: createdAt), now: createdAt)
    _ = index.insert(.init(id: recent, createdAt: createdAt + 1800), now: createdAt + 1800)

    let new = UUID()
    let dropped = index.insert(.init(id: new, createdAt: createdAt + 3600), now: createdAt + 3600)

    #expect(dropped == [old])
    #expect(index.flows.map(\.id) == [recent, new])
  }

  @Test
  func indexRoundTrips() throws {
    var index = PendingFlowIndex()
    _ = index.insert(.init(id: id, createdAt: createdAt), now: createdAt)

    let data = try index.encoded()

    expectNoDifference(
      String(decoding: data, as: UTF8.self),
      #"{"flows":[{"created_at":"2026-09-22T10:42:45Z","id":"6C69F399-BE1B-467A-9C53-D3753ABDD2DF"}]}"#
    )
    #expect(try PendingFlowIndex.decode(data) == index)

    index.remove(id: id)
    #expect(index.flows.isEmpty)
  }
}
