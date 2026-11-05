//
//  ResubscribeView.swift
//  Examples
//
//  Demonstrates `RealtimeChannelEvent.resubscribed`: changes sent while a channel was away are
//  lost, so the view fetches its data again when the channel joins again.
//

import IdentifiedCollections
@_spi(Experimental) import Supabase
import SwiftUI

struct ResubscribeView: View {
  @State var todos: IdentifiedArrayOf<Todo> = []
  @State var reloads: [Reload] = []
  @State var rejoinRequests = 0
  @State var error: Error?

  var body: some View {
    List {
      Section {
        Text(
          """
          A channel that joins again was away, so it missed every change sent in between. \
          Tap the button to close the socket and join the channel again: the join emits \
          `.resubscribed`, and the view fetches the todos again.
          """
        )
        .font(.caption)
        .foregroundColor(.secondary)
      }

      Section {
        Button("Disconnect and join again") {
          rejoinRequests += 1
        }
      }

      Section("Reloads (\(reloads.count))") {
        ForEach(reloads) { reload in
          HStack {
            Text("Fetched \(reload.count) todos")
            Spacer()
            Text(reload.timestamp, style: .time)
              .font(.caption)
              .foregroundColor(.secondary)
          }
        }
      }

      if let error {
        Section {
          ErrorText(error)
        }
      }

      Section("Todos (\(todos.count))") {
        ForEach(todos) { todo in
          TodoListRow(todo: todo) {}
        }
      }
    }
    .navigationTitle("Resubscribe")
    .gitHubSourceLink()
    .task {
      await observeTodos()
    }
    // Ends with the view, so a rejoin never outlives the screen. The task runs once at 0, then
    // again for each tap.
    .task(id: rejoinRequests) {
      guard rejoinRequests > 0 else { return }
      await rejoin()
    }
  }

  private let channelName = "resubscribe-example"

  /// `disconnect()` leaves a subscribed channel `.unsubscribed`, and `connect()` does not rejoin
  /// it. Subscribing again joins it, and the join emits `.resubscribed`.
  func rejoin() async {
    await supabaseClient.realtime.disconnect()
    // Leaving the view removes the channel while `disconnect()` runs. Asking for it again would
    // create a channel that nothing removes.
    guard !Task.isCancelled else { return }
    do {
      try await supabaseClient.channel(channelName).subscribe()
    } catch {
      if !Task.isCancelled {
        self.error = error
      }
    }
  }

  func observeTodos() async {
    let channel = await supabaseClient.channel(channelName)
    let changes = await channel.postgresChanges(for: Todo.self)
    let events = await channel.events()

    do {
      error = nil
      try await channel.subscribe()
      await reload()

      await withTaskGroup(of: Void.self) { group in
        group.addTask { await reloadOnResubscribe(events) }
        group.addTask { await apply(changes) }
      }
    } catch {
      if !Task.isCancelled {
        self.error = error
      }
    }

    await supabaseClient.removeChannel(channel)
  }

  func reloadOnResubscribe(_ events: AsyncStream<RealtimeChannelEvent>) async {
    for await event in events where event == .resubscribed {
      await reload()
    }
  }

  func apply(_ changes: AsyncStream<TypedPostgresChange<Todo>>) async {
    for await change in changes {
      do {
        try todos.apply(change)
      } catch {
        self.error = error
      }
    }
  }

  func reload() async {
    do {
      todos = try await .fetchTodos()
      reloads.insert(Reload(count: todos.count), at: 0)
    } catch {
      if !Task.isCancelled {
        self.error = error
      }
    }
  }
}

struct Reload: Identifiable {
  let id = UUID()
  let count: Int
  let timestamp = Date()
}
