import Foundation
import Testing

@testable import Realtime

@Suite
struct RealtimeChannelConfigurationTests {
  let client = RealtimeClient(
    url: URL(string: "https://localhost:54321/realtime/v1")!,
    options: RealtimeClientOptions()
  )

  @Test
  func defaultConfigurationIsPublicWithEveryOptionOff() {
    let configuration = RealtimeChannelConfiguration()

    #expect(!configuration.isPrivate)
    #expect(!configuration.broadcast.receiveOwnMessages)
    #expect(!configuration.broadcast.acknowledge)
    #expect(configuration.broadcast.replay == nil)
    #expect(!configuration.broadcast.waitForReplication)
    #expect(configuration.presence.key == nil)
    #expect(!configuration.postgresChanges.waitForSubscription)
    #expect(configuration.postgresChanges.subscriptionTimeout == .seconds(15))
  }

  @Test
  func channelKeepsConfiguration() async {
    let channel = await client.channel("room") { $0.isPrivate = true }

    #expect(channel.configuration.isPrivate)
  }

  // `reportIssue` reaches `withKnownIssue` only on Darwin.
  #if canImport(Darwin)
    @Test
    func differentConfigurationReportsIssueAndReturnsExisting() async {
      let first = await client.channel("room")

      var second: RealtimeChannel?
      await withKnownIssue {
        second = await client.channel("room") { $0.isPrivate = true }
      }

      #expect(first === second)
      #expect(second?.configuration.isPrivate == false)
    }
  #endif

  @Test
  func sameConfigurationReportsNoIssue() async {
    let first = await client.channel("room") { $0.broadcast.acknowledge = true }
    let second = await client.channel("room") { $0.broadcast.acknowledge = true }

    #expect(first === second)
  }
}
