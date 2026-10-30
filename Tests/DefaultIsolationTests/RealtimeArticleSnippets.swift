//
//  RealtimeArticleSnippets.swift
//  DefaultIsolationTests
//

#if canImport(SwiftUI)
  import Foundation
  import Supabase
  import SwiftUI

  // Compile-time check of the code in Sources/Realtime/Realtime.docc, under the default
  // `MainActor` isolation of a new Xcode app target. Nothing here runs.

  private let supabase = SupabaseClient(
    supabaseURL: URL(string: "https://project-ref.supabase.co")!,
    supabaseKey: "publishable-key",
    options: SupabaseClientOptions()
  )

  private struct ChatMessage: Decodable, Identifiable {
    var id: UUID
    var text: String
  }

  private enum Landing {
    static func run() async throws {
      let channel = await supabase.channel("room:42")
      let messages = await channel.broadcasts(event: "message")

      try await channel.subscribe()
      for await message in messages {
        let chat = try message.decode(as: ChatMessage.self)
        print(chat.text)
      }
      await supabase.removeChannel(channel)
    }
  }

  private enum Lifetime {
    struct RoomView: View {
      let roomID: UUID
      @State private var messages: [ChatMessage] = []

      var body: some View {
        List(messages) { Text($0.text) }
          .task(id: roomID) {
            let channel = await supabase.channel("room:\(roomID)")
            let incoming = await channel.broadcasts(event: "message")
            do {
              try await channel.subscribe()
              for await message in incoming {
                if let chat = try? message.decode(as: ChatMessage.self) {
                  messages.append(chat)
                }
              }
            } catch {
              // A RealtimeError from subscribe(), or CancellationError.
            }
            await supabase.removeChannel(channel)
          }
      }
    }

    @Observable final class Model {
      func reload() async {}
      func apply(_ change: PostgresChange) async {}
    }

    struct RejoinView: View {
      let roomID: UUID
      let model: Model

      var body: some View {
        EmptyView()
          .task(id: roomID) {
            let channel = await supabase.channel("room:\(roomID)")
            let changes = await channel.postgresChanges(table: "messages")
            let events = await channel.events()
            try? await channel.subscribe()

            await withTaskGroup { group in
              group.addTask {
                for await event in events where event == .resubscribed {
                  await model.reload()
                }
              }
              group.addTask {
                for await change in changes {
                  await model.apply(change)
                }
              }
            }
            await supabase.removeChannel(channel)
          }
      }
    }
  }

  private enum Isolation {
    @MainActor @Observable
    final class RoomModel {
      var isOnline = false
      var userID = UUID()

      func refresh(_ channel: RealtimeChannel) async {
        isOnline = await channel.status.isSubscribed
      }
    }

    nonisolated struct Status: Codable {
      var name: String
      var typing: Bool
    }

    static func run(model: RoomModel) async throws {
      let key = model.userID.uuidString
      let channel = await supabase.channel("room:42") { config in
        config.presence.key = key
      }
      _ = channel.topic
      _ = channel.configuration

      try await channel.track(Status(name: "Ana", typing: false))
    }
  }

  private enum TypedPayloads {
    struct Cursor: Decodable {
      var x: Double
      var y: Double
    }

    struct Todo: Decodable {
      var id: Int
    }

    static func move(_ cursor: Cursor) {}
    static func upsert(_ todo: Todo) {}
    static func remove(_ id: Int) {}

    static func run(_ channel: RealtimeChannel) async throws {
      for await message in await channel.broadcasts(event: "cursor") {
        do {
          let cursor = try message.decode(as: Cursor.self)
          move(cursor)
        } catch {
          print("Skipped a cursor: \(error)")
        }
      }

      let todos = await channel.postgresChanges(of: Todo.self, table: "todos")
      try await channel.subscribe()

      for await change in todos {
        switch change.kind {
        case .insert, .update:
          if let todo = try? change.row() { upsert(todo) }
        case .delete:
          if let id = change.oldRecord?["id"]?.intValue { remove(id) }
        default:
          break
        }
      }
    }
  }

  private enum PresenceArticle {
    nonisolated struct Status: Codable {
      var name: String
      var typing: Bool
    }

    static func show(_ users: [String: [Status]]) {}

    static func run(userID: UUID, currentStatus: Status) async throws {
      let key = userID.uuidString
      let channel = await supabase.channel("room:42") { $0.presence.key = key }
      let online = await channel.presenceStates()

      try await channel.subscribe()
      try await channel.track(Status(name: "Ana", typing: false))

      for await state in online {
        let users = try state.decode(as: Status.self)
        show(users)
      }

      for await event in await channel.events() where event == .resubscribed {
        try? await channel.track(currentStatus)
      }
    }
  }

  private enum Auth {
    enum Session {
      static func currentAccessToken() async throws -> String { "" }
    }

    static func run(publishableKey: String, newToken: String) async {
      let session = Session.self
      let options = RealtimeClientOptions(
        headers: ["apikey": publishableKey],
        accessToken: { try await session.currentAccessToken() }
      )
      let realtime = RealtimeClient(
        url: URL(string: "https://<project-ref>.supabase.co/realtime/v1")!,
        options: options
      )

      let channel = await supabase.channel("room:42") { $0.isPrivate = true }
      do {
        try await channel.subscribe()
      } catch let error as RealtimeError where error.kind == .unauthorized {
        // A policy denied this user, or nobody is signed in.
      } catch {}

      await realtime.setAuth(newToken)  // Send this token now.
      await realtime.setAuth()  // Ask the closure again.
    }
  }

  private enum ConnectionBehavior {
    @Observable final class Banner {
      var isBannerVisible = false
      var bannerText = ""

      func run() async {
        for await status in await supabase.realtime.statusChanges() {
          isBannerVisible = !status.isConnected
          if case .reconnecting(let attempt, let retryIn, _) = status {
            bannerText = "Reconnecting in \(retryIn) (attempt \(attempt + 1))"
          }
        }
      }
    }

    struct MessageList: View {
      let roomID: UUID
      var body: some View { EmptyView() }
    }

    struct RoomView: View {
      let roomID: UUID
      @Environment(\.scenePhase) private var scenePhase

      func show(_ message: BroadcastMessage) {}

      var body: some View {
        MessageList(roomID: roomID)
          .task(id: scenePhase == .background) {
            guard scenePhase != .background else { return }
            let channel = await supabase.channel("room:\(roomID)")
            let messages = await channel.broadcasts(event: "message")
            try? await channel.subscribe()
            for await message in messages {
              show(message)
            }
            await supabase.removeChannel(channel)
          }
      }
    }
  }

  private enum HighRateFeeds {
    nonisolated struct Tick: Decodable {
      let symbol: String
      let price: Double
    }

    @MainActor @Observable
    final class PriceBoard {
      var prices: [String: Double] = [:]
      func apply(_ snapshot: [String: Double]) { prices = snapshot }
    }

    @concurrent
    static func pump(_ ticks: AsyncStream<BroadcastMessage>, into board: PriceBoard) async {
      var latest: [String: Double] = [:]
      var lastPublish = ContinuousClock.now
      for await message in ticks {
        guard let tick = try? message.decode(as: Tick.self) else { continue }
        latest[tick.symbol] = tick.price
        if ContinuousClock.now - lastPublish >= .milliseconds(100) {
          await board.apply(latest)
          lastPublish = .now
        }
      }
    }

    struct PricesView: View {
      let board: PriceBoard

      var body: some View {
        EmptyView()
          .task {
            let channel = await supabase.channel("prices")
            let ticks = await channel.broadcasts(event: "tick")
            try? await channel.subscribe()
            await pump(ticks, into: board)
            await supabase.removeChannel(channel)
          }
      }
    }
  }

  private enum CustomTransports {
    nonisolated static func isPinned(_ trust: SecTrust) -> Bool { true }

    nonisolated final class PinningDelegate: NSObject, URLSessionDelegate {
      func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
      ) {
        guard let trust = challenge.protectionSpace.serverTrust, isPinned(trust) else {
          completionHandler(.cancelAuthenticationChallenge, nil)
          return
        }
        completionHandler(.useCredential, URLCredential(trust: trust))
      }
    }

    static func pinning() {
      var options = RealtimeClientOptions()
      options.webSocketTransport = URLSessionWebSocketTransport(delegate: PinningDelegate())
    }

    actor StubConnection: WebSocketConnection {
      nonisolated let events: AsyncStream<WebSocketEvent>
      private nonisolated let continuation: AsyncStream<WebSocketEvent>.Continuation
      private(set) var sent: [WebSocketFrame] = []

      init() {
        (events, continuation) = AsyncStream.makeStream(of: WebSocketEvent.self)
      }

      func send(_ frame: WebSocketFrame) async throws {
        sent.append(frame)
      }

      nonisolated func close(code: WebSocketCloseCode, reason: String?) {
        continuation.yield(.closed(code: code, reason: reason))
        continuation.finish()
      }

      nonisolated func receive(_ text: String) {
        continuation.yield(.frame(.text(text)))
      }
    }

    nonisolated struct StubTransport: WebSocketTransport {
      let connection: StubConnection

      func connect(to url: URL, headerFields: HTTPFields) async throws -> any WebSocketConnection {
        connection
      }
    }

    static func reply(_ connection: StubConnection) {
      connection.receive(
        #"["1","1","realtime:room","phx_reply",{"status":"ok","response":{"postgres_changes":[]}}]"#
      )
    }
  }
#endif
