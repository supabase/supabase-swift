import XCTest

@testable import Realtime

final class ChannelTopicTests: XCTestCase {
  func testRawValue() {
    XCTAssertEqual(ChannelTopic.all, ChannelTopic(rawValue: "realtime:*"))
    XCTAssertEqual(ChannelTopic.all, ChannelTopic(rawValue: "*"))
    XCTAssertEqual(ChannelTopic.schema("public"), ChannelTopic(rawValue: "realtime:public"))
    XCTAssertEqual(
      ChannelTopic.table("users", schema: "public"), ChannelTopic(rawValue: "realtime:public:users")
    )
    XCTAssertEqual(
      ChannelTopic.column("email", value: "mail@supabase.io", table: "users", schema: "public"),
      ChannelTopic(rawValue: "realtime:public:users:email=eq.mail@supabase.io")
    )
    XCTAssertEqual(ChannelTopic.heartbeat, ChannelTopic(rawValue: "phoenix"))
  }
}
