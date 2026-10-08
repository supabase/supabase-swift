//
//  StreamingChatView.swift
//  Examples
//
//  Streams a function's server-sent events into a chat bubble.
//

import Supabase
import SwiftUI

struct StreamingChatView: View {
  @State private var prompt = "Tell me about streaming"
  @State private var reply = ""
  @State private var request: String?
  @State private var error: Error?

  var body: some View {
    List {
      Section {
        Text(
          "Edge Functions can answer with text/event-stream. The reply renders as each event arrives."
        )
        .font(.caption)
        .foregroundColor(.secondary)
      }

      Section("Prompt") {
        TextField("Prompt", text: $prompt)

        Button("Send") {
          reply = ""
          error = nil
          request = prompt
        }
        .disabled(prompt.isEmpty || isStreaming)
      }

      if !reply.isEmpty || isStreaming {
        Section("Reply") {
          Text(reply.isEmpty ? "…" : reply)
            .font(.body)
        }
      }

      if let error {
        Section {
          ErrorText(error)
        }
      }

      Section("Swift Code") {
        CodeExample(
          code: """
            let response = try await supabase.functions.stream("chat", body: .json(["prompt": prompt]))
            for try await chunk in response.body {
              // frame server-sent events on the blank line that ends each one
            }
            """)
      }
    }
    .navigationTitle("Streaming Chat")
    .gitHubSourceLink()
    // `.task(id:)` cancels the running stream when the view disappears or a new prompt is sent.
    .task(id: request) {
      guard let request else { return }
      await stream(prompt: request)
    }
  }

  private var isStreaming: Bool { request != nil }

  @MainActor
  private func stream(prompt: String) async {
    defer { request = nil }
    do {
      let response = try await supabase.functions.stream("chat", body: .json(["prompt": prompt]))

      var buffer = Data()
      for try await chunk in response.body {
        buffer.append(contentsOf: chunk)
        while let range = buffer.range(of: Data("\n\n".utf8)) {
          let event = String(decoding: buffer[..<range.lowerBound], as: UTF8.self)
          buffer.removeSubrange(..<range.upperBound)
          let data = event.split(separator: "\n")
            .filter { $0.hasPrefix("data:") }
            .map { $0.dropFirst(5).trimmingCharacters(in: .whitespaces) }
            .joined(separator: "\n")
          if data == "[DONE]" { return }
          if let delta = try? JSONDecoder().decode(Delta.self, from: Data(data.utf8)) {
            reply += delta.delta
          }
        }
      }
    } catch is CancellationError {
      // the user left the screen or sent a new prompt
    } catch {
      self.error = error
    }
  }

  private struct Delta: Decodable {
    let delta: String
  }
}
