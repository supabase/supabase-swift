//
//  RealtimeBehaviorTests.swift
//
//
//  Created by Guilherme Souza on 23/10/26.
//

#if !os(Android) && !os(Linux)
  import ConcurrencyExtras
  import Foundation
  import Network
  import RealtimeV2
  import Testing

  @Suite(
    .serialized,
    .timeLimit(.minutes(1)),
    .enabled(if: ProcessInfo.processInfo.environment["INTEGRATION_TESTS"] != nil)
  )
  struct RealtimeBehaviorTests {
    @Test
    func connectReportsStatusWithoutAwait() async throws {
      let client = makeClient()
      #expect(client.status == .disconnected)

      try await client.connect()

      #expect(client.status == .connected)
      await client.removeAllChannels()
    }

    @Test
    func subscribeWithErrorReportsStatusTransitions() async throws {
      let client = makeClient()
      let channel = client.channel(uniqueTopic())
      let statuses = channel.statusChange

      try await channel.subscribeWithError()

      #expect(channel.status == .subscribed)
      let seen = try await collect(statuses, "channel statuses") { $0.last == .subscribed }
      #expect(seen == [.unsubscribed, .subscribing, .subscribed])
      await client.removeAllChannels()
    }

    @Test
    func broadcastWithAckReachesOwnStream() async throws {
      let client = makeClient()
      let channel = client.channel(uniqueTopic()) {
        $0.broadcast.acknowledgeBroadcasts = true
        $0.broadcast.receiveOwnBroadcasts = true
      }
      let messages = channel.broadcastStream(event: "ping")
      try await channel.subscribeWithError()

      try await channel.broadcast(event: "ping", message: Note(text: "to self"))

      let received = try await collect(messages, "own broadcast", count: 1)
      #expect(received[0]["event"]?.stringValue == "ping")
      #expect(received[0]["payload"]?.objectValue?["text"]?.stringValue == "to self")
      await client.removeAllChannels()
    }

    @Test
    func binaryBroadcastReachesSecondClient() async throws {
      let topic = uniqueTopic()
      let receiver = makeClient()
      let sender = makeClient()
      let receiving = receiver.channel(topic)
      let frames = receiving.broadcastDataStream(event: "bytes")
      try await receiving.subscribeWithError()
      let sending = sender.channel(topic)
      try await sending.subscribeWithError()
      let bytes = Data([0x00, 0x01, 0x7F, 0x80, 0xFE, 0xFF])

      try await sending.broadcast(event: "bytes", data: bytes)

      let received = try await collect(frames, "binary broadcast", count: 1)
      #expect(received == [bytes])
      await sender.removeAllChannels()
      await receiver.removeAllChannels()
    }

    @Test
    func presenceChangeReportsJoinAndLeave() async throws {
      let topic = uniqueTopic()
      let observer = makeClient()
      let member = makeClient()
      let observing = observer.channel(topic)
      let changes = observing.presenceChange()
      try await observing.subscribeWithError()
      let joining = member.channel(topic)
      try await joining.subscribeWithError()

      try await joining.track(Note(text: "member"))
      let joined = try await collect(changes, "presence join") { $0.last?.joins.isEmpty == false }
      #expect(try joined.last?.decodeJoins(as: Note.self) == [Note(text: "member")])

      await member.removeAllChannels()
      let left = try await collect(changes, "presence leave") { $0.last?.leaves.isEmpty == false }
      #expect(try left.last?.decodeLeaves(as: Note.self) == [Note(text: "member")])
      await observer.removeAllChannels()
    }

    @Test
    func postgresChangeDeliversInsertsAndTypedEqFilter() async throws {
      let client = makeClient()
      let otherKey = "rv1-\(UUID().uuidString)"
      let matchingKey = "rv1-\(UUID().uuidString)"
      let channel = client.channel(uniqueTopic())
      let inserts = channel.postgresChange(
        InsertAction.self, schema: "public", table: "key_value_storage")
      let filtered = channel.postgresChange(
        InsertAction.self, schema: "public", table: "key_value_storage",
        filter: .eq("key", value: matchingKey))
      let system = channel.system()
      try await channel.subscribeWithError()
      _ = try await collect(system, "postgres_changes ready") {
        $0.last?.payload["extension"]?.stringValue == "postgres_changes"
      }

      try await LocalStack.run({
        try await LocalStack.insertRow(key: otherKey)
        try await LocalStack.insertRow(key: matchingKey)

        let all = try await collect(inserts, "unfiltered inserts", count: 2)
        #expect(all.map { $0.record["key"]?.stringValue } == [otherKey, matchingKey])
        let matching = try await collect(filtered, "filtered insert", count: 1)
        #expect(matching[0].record["key"]?.stringValue == matchingKey)
      }) {
        try await LocalStack.deleteRows(keys: [otherKey, matchingKey])
      }
      await client.removeAllChannels()
    }

    @Test
    func privateChannelRejectsAnonSubscribe() async throws {
      try await LocalStack.withAuthenticatedOnlyTopic { topic in
        let client = makeClient(LocalStack.failFastOptions)
        let channel = client.channel(topic) { $0.isPrivate = true }

        await #expect(throws: (any Error).self) {
          try await channel.subscribeWithError()
        }

        #expect(channel.status == .unsubscribed)
        await client.removeAllChannels()
      }
    }

    @Test
    func privateChannelAcceptsUserJWTFromSetAuth() async throws {
      try await LocalStack.withAuthenticatedOnlyTopic { topic in
        try await LocalStack.withSignedInUser { accessToken in
          let client = makeClient(LocalStack.failFastOptions)
          await client.setAuth(accessToken)
          let channel = client.channel(topic) { $0.isPrivate = true }

          try await channel.subscribeWithError()

          #expect(channel.status == .subscribed)
          await client.removeAllChannels()
        }
      }
    }

    @Test
    func httpSendDeliversWithoutSubscription() async throws {
      let topic = uniqueTopic()
      let receiver = makeClient()
      let sender = makeClient(
        RealtimeClientOptions(
          headers: LocalStack.anonHeaders, accessToken: { DotEnv.SUPABASE_PUBLISHABLE_KEY }))
      let receiving = receiver.channel(topic)
      let messages = receiving.broadcastStream(event: "rest")
      try await receiving.subscribeWithError()
      let sending = sender.channel(topic)

      try await sending.httpSend(event: "rest", message: Note(text: "over http"))

      let received = try await collect(messages, "http broadcast", count: 1)
      #expect(received[0]["payload"]?.objectValue?["text"]?.stringValue == "over http")
      #expect(sending.status == .unsubscribed)
      #expect(sender.status == .disconnected)
      await receiver.removeAllChannels()
    }

    @Test
    func badAPIKeyEndsDisconnected() async throws {
      let client = makeClient(RealtimeClientOptions(headers: ["apikey": "not-a-valid-key"]))
      let statuses = client.statusChange

      try? await client.connect()

      #expect(client.status == .disconnected)
      let seen = try await collect(statuses, "client statuses", count: 3)
      #expect(seen == [.disconnected, .connecting, .disconnected])
    }

    @Test
    func resubscribeAfterUnsubscribeDeliversBroadcast() async throws {
      let client = makeClient()
      let topic = uniqueTopic()
      let first = client.channel(topic) { $0.broadcast.receiveOwnBroadcasts = true }
      try await first.subscribeWithError()
      await first.unsubscribe()
      #expect(first.status == .unsubscribed)

      let channel = client.channel(topic) { $0.broadcast.receiveOwnBroadcasts = true }
      let messages = channel.broadcastStream(event: "again")
      try await channel.subscribeWithError()
      try await channel.broadcast(event: "again", message: Note(text: "second join"))

      #expect(channel.status == .subscribed)
      let received = try await collect(messages, "broadcast after resubscribe", count: 1)
      #expect(received[0]["payload"]?.objectValue?["text"]?.stringValue == "second join")
      await client.removeAllChannels()
    }

    @Test
    func removeChannelDuringReconnectDoesNotRejoin() async throws {
      let relay = try TCPRelay(upstream: LocalStack.url)
      defer { relay.stop() }
      let port = try await relay.start()
      let client = makeClient(
        url: URL(string: "http://127.0.0.1:\(port)/realtime/v1")!,
        RealtimeClientOptions(headers: LocalStack.anonHeaders, reconnectDelay: 0.2))
      let removed = client.channel(uniqueTopic())
      let kept = client.channel(uniqueTopic())
      try await removed.subscribeWithError()
      try await kept.subscribeWithError()
      let clientStatuses = client.statusChange
      let keptStatuses = kept.statusChange

      relay.cutAndHold()
      _ = try await collect(clientStatuses, "reconnect start") { $0.last == .connecting }
      await client.removeChannel(removed)
      let removedHistory = record(removed.statusChange)
      relay.release()

      _ = try await collect(keptStatuses, "kept channel rejoin") {
        $0.suffix(2) == [.subscribing, .subscribed]
      }
      #expect(client.status == .connected)
      #expect(removed.status == .unsubscribed)
      #expect(!client.channels.values.contains { $0 === removed })
      #expect(!removedHistory.value.contains(.subscribing))
      await client.removeAllChannels()
    }

    @Test
    func cancelledStreamLeavesSiblingStreamDelivering() async throws {
      let client = makeClient()
      let channel = client.channel(uniqueTopic()) { $0.broadcast.receiveOwnBroadcasts = true }
      let cancelled = channel.broadcastStream(event: "shared")
      let sibling = channel.broadcastStream(event: "shared")
      try await channel.subscribeWithError()
      let reader = Task {
        var count = 0
        for await _ in cancelled { count += 1 }
        return count
      }

      reader.cancel()
      let cancelledCount = await reader.value
      try await channel.broadcast(event: "shared", message: Note(text: "after cancel"))

      let received = try await collect(sibling, "sibling stream", count: 1)
      #expect(received[0]["payload"]?.objectValue?["text"]?.stringValue == "after cancel")
      #expect(cancelledCount == 0)
      await client.removeAllChannels()
    }

    @Test
    func heartbeatReportsSentThenOK() async throws {
      let client = makeClient(
        RealtimeClientOptions(headers: LocalStack.anonHeaders, heartbeatInterval: 1))
      let beats = client.heartbeat
      let channel = client.channel(uniqueTopic())

      try await channel.subscribeWithError()

      let seen = try await collect(beats, "heartbeat", within: .seconds(5), count: 2)
      #expect(seen == [.sent, .ok])
      await client.removeAllChannels()
    }
  }

  private struct Note: Codable, Equatable {
    let text: String
  }

  private func uniqueTopic() -> String {
    "rv1-\(UUID().uuidString)"
  }

  private func makeClient(
    url: URL = LocalStack.realtimeURL,
    _ options: RealtimeClientOptions = RealtimeClientOptions(headers: LocalStack.anonHeaders)
  ) -> RealtimeClientV2 {
    RealtimeClientV2(url: url, options: options)
  }

  private struct Failure: Error, CustomStringConvertible {
    let description: String
  }

  private func collect<Element: Sendable>(
    _ stream: AsyncStream<Element>,
    _ what: String,
    within limit: Duration = .seconds(10),
    count: Int
  ) async throws -> [Element] {
    try await collect(stream, what, within: limit) { $0.count == count }
  }

  private func collect<Element: Sendable>(
    _ stream: AsyncStream<Element>,
    _ what: String,
    within limit: Duration = .seconds(10),
    until done: @escaping @Sendable ([Element]) -> Bool
  ) async throws -> [Element] {
    let seen = LockIsolated<[Element]>([])
    let finished = try await withThrowingTaskGroup(of: Bool.self) { group in
      group.addTask {
        for await element in stream {
          let snapshot = seen.withValue {
            $0.append(element)
            return $0
          }
          if done(snapshot) { return true }
        }
        return false
      }
      group.addTask {
        try await Task.sleep(for: limit)
        return false
      }
      defer { group.cancelAll() }
      return try await group.next() ?? false
    }
    guard finished else {
      throw Failure(description: "\(what) not observed within \(limit), saw \(seen.value)")
    }
    return seen.value
  }

  private func record<Element: Sendable>(_ stream: AsyncStream<Element>) -> LockIsolated<[Element]>
  {
    let history = LockIsolated<[Element]>([])
    Task {
      for await element in stream { history.withValue { $0.append(element) } }
    }
    return history
  }

  private enum LocalStack {
    static let url = URL(string: DotEnv.SUPABASE_URL)!
    static let realtimeURL = url.appendingPathComponent("realtime/v1")
    static let studioQueryURL = URL(
      string: "http://127.0.0.1:54323/api/platform/pg-meta/default/query")!
    static let anonHeaders = ["apikey": DotEnv.SUPABASE_PUBLISHABLE_KEY]
    static let failFastOptions = RealtimeClientOptions(
      headers: anonHeaders, timeoutInterval: 3, maxRetryAttempts: 1)

    static func insertRow(key: String) async throws {
      try await send(
        "POST", url.appendingPathComponent("rest/v1/key_value_storage"),
        key: DotEnv.SUPABASE_PUBLISHABLE_KEY, json: ["key": key])
    }

    static func deleteRows(keys: [String]) async throws {
      var components = URLComponents(
        url: url.appendingPathComponent("rest/v1/key_value_storage"), resolvingAgainstBaseURL: false
      )!
      components.queryItems = [
        URLQueryItem(name: "key", value: "in.(\(keys.joined(separator: ",")))")
      ]
      try await send("DELETE", components.url!, key: DotEnv.SUPABASE_PUBLISHABLE_KEY)
    }

    static func withAuthenticatedOnlyTopic(_ body: (String) async throws -> Void) async throws {
      let topic = uniqueTopic()
      let policy = "rv1 authenticated reads \(topic)"
      try await sql(
        """
        create policy "\(policy)" on realtime.messages for select to authenticated
        using (realtime.topic() = '\(topic)')
        """)
      try await run({ try await body(topic) }) {
        try await sql(#"drop policy if exists "\#(policy)" on realtime.messages"#)
      }
    }

    static func withSignedInUser(_ body: (String) async throws -> Void) async throws {
      let email = "rv1-\(UUID().uuidString.lowercased())@example.com"
      let password = "rv1-\(UUID().uuidString)"
      let user = try await send(
        "POST", url.appendingPathComponent("auth/v1/admin/users"), key: DotEnv.SUPABASE_SECRET_KEY,
        json: ["email": email, "password": password, "email_confirm": true])
      let userURL = url.appendingPathComponent("auth/v1/admin/users/\(try string("id", in: user))")
      try await run({
        let session = try await send(
          "POST", URL(string: "\(DotEnv.SUPABASE_URL)/auth/v1/token?grant_type=password")!,
          key: DotEnv.SUPABASE_PUBLISHABLE_KEY, json: ["email": email, "password": password])
        try await body(try string("access_token", in: session))
      }) {
        try await send("DELETE", userURL, key: DotEnv.SUPABASE_SECRET_KEY)
      }
    }

    static func run(
      _ body: () async throws -> Void, thenCleanUp cleanUp: () async throws -> Void
    ) async throws {
      do {
        try await body()
      } catch {
        try? await cleanUp()
        throw error
      }
      try await cleanUp()
    }

    private static func sql(_ query: String) async throws {
      try await send(
        "POST", studioQueryURL, key: DotEnv.SUPABASE_SECRET_KEY, json: ["query": query])
    }

    private static func string(_ field: String, in data: Data) throws -> String {
      let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
      return try #require(object?[field] as? String, "response has no \(field)")
    }

    @discardableResult
    private static func send(
      _ method: String, _ url: URL, key: String, json: [String: Any]? = nil
    ) async throws -> Data {
      var request = URLRequest(url: url)
      request.httpMethod = method
      request.setValue(key, forHTTPHeaderField: "apikey")
      request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
      if let json {
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: json)
      }
      let (data, response) = try await URLSession.shared.data(for: request)
      let status = (response as? HTTPURLResponse)?.statusCode ?? 0
      guard (200..<300).contains(status) else {
        throw Failure(
          description:
            "\(method) \(url.path) returned \(status): \(String(decoding: data, as: UTF8.self))"
        )
      }
      return data
    }
  }

  private final class TCPRelay: @unchecked Sendable {
    private let queue = DispatchQueue(label: "RealtimeBehaviorTests.TCPRelay")
    private let listener: NWListener
    private let upstream: NWEndpoint
    private var isHolding = false
    private var held: [NWConnection] = []
    private var bridged: [NWConnection] = []

    init(upstream url: URL) throws {
      listener = try NWListener(using: .tcp, on: .any)
      upstream = .hostPort(
        host: NWEndpoint.Host(url.host ?? "127.0.0.1"),
        port: NWEndpoint.Port(rawValue: UInt16(url.port ?? 80))!
      )
    }

    func start() async throws -> UInt16 {
      try await withCheckedThrowingContinuation { continuation in
        listener.stateUpdateHandler = { [listener] state in
          switch state {
          case .ready:
            listener.stateUpdateHandler = nil
            continuation.resume(returning: listener.port!.rawValue)
          case .failed(let error):
            listener.stateUpdateHandler = nil
            continuation.resume(throwing: error)
          default:
            break
          }
        }
        listener.newConnectionHandler = { [unowned self] connection in
          if isHolding { held.append(connection) } else { bridge(connection) }
        }
        listener.start(queue: queue)
      }
    }

    func cutAndHold() {
      queue.sync {
        isHolding = true
        bridged.forEach { $0.cancel() }
        bridged = []
      }
    }

    func release() {
      queue.sync {
        isHolding = false
        held.forEach(bridge)
        held = []
      }
    }

    func stop() {
      queue.sync {
        listener.cancel()
        (held + bridged).forEach { $0.cancel() }
      }
    }

    private func bridge(_ client: NWConnection) {
      let server = NWConnection(to: upstream, using: .tcp)
      bridged += [client, server]
      pipe(from: client, to: server)
      pipe(from: server, to: client)
      client.start(queue: queue)
      server.start(queue: queue)
    }

    private func pipe(from source: NWConnection, to destination: NWConnection) {
      source.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) {
        [weak self] data, _, isComplete, error in
        if let data, !data.isEmpty {
          destination.send(content: data, completion: .contentProcessed { _ in })
        }
        if isComplete || error != nil {
          source.cancel()
          destination.cancel()
        } else {
          self?.pipe(from: source, to: destination)
        }
      }
    }
  }
#endif
