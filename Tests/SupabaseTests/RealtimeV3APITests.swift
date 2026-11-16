import Foundation
import Supabase
import Testing

@Suite
struct SupabaseClientRealtimeV3APITests {
  // Linux has no initializer without `options`: Auth has no default storage there.
  let client = SupabaseClient(
    supabaseURL: URL(string: "https://project-ref.supabase.co")!,
    supabaseKey: "publishable.api.key",
    options: SupabaseClientOptions(
      auth: SupabaseClientOptions.AuthOptions(storage: AuthLocalStorageMock())
    )
  )

  @Test
  @MainActor
  func channelConfigureAppliesTheClosure() {
    let channel = client.channel("room") { configuration in
      configuration.isPrivate = true
      configuration.broadcast.receivesOwnMessages = true
    }

    #expect(channel.configuration.isPrivate)
    #expect(channel.configuration.broadcast.receivesOwnMessages)
  }

  @Test
  @MainActor
  func v2ChannelCallSitesKeepTheirMeaning() {
    let plain = client.channel("plain")
    let labelled = client.channel("labelled", options: { $0.isPrivate = true })
    let trailing = client.channel("trailing") { $0.isPrivate = true }

    #expect(plain.topic == "realtime:plain")
    #expect(!plain.configuration.isPrivate)
    #expect(labelled.configuration.isPrivate)
    #expect(trailing.configuration.isPrivate)
    #expect(client.channels.count == 3)
  }
}
