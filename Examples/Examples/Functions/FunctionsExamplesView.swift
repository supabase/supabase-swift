//
//  FunctionsExamplesView.swift
//  Examples
//
//  Demonstrates Supabase Edge Functions
//

import Supabase
import SwiftUI

struct FunctionsExamplesView: View {
  @State var name: String = "Swift User"
  @State var result: String?
  @State var error: Error?
  @State var isLoading = false

  var body: some View {
    List {
      Section {
        Text("Invoke serverless Edge Functions deployed on Supabase")
          .font(.caption)
          .foregroundColor(.secondary)
      }

      Section("Hello World Function") {
        TextField("Your name", text: $name)

        Button("Invoke Function") {
          Task {
            await invokeHelloWorld()
          }
        }
        .disabled(isLoading)

        if isLoading {
          ProgressView()
        }

        if let result {
          VStack(alignment: .leading, spacing: 8) {
            Text("Response:")
              .font(.caption)
              .foregroundColor(.secondary)
            Text(result)
              .font(.body)
          }
        }
      }

      if let error {
        Section {
          ErrorText(error)
        }
      }

      Section("Code Examples") {
        CodeExample(
          code: """
            // Invoke a function with parameters
            struct HelloWorldRequest: Encodable {
              let name: String
            }

            struct HelloWorldResponse: Decodable {
              let message: String
            }

            let request = HelloWorldRequest(name: "\(name)")

            let response: HelloWorldResponse = try await supabase
              .functions
              .invoke(
                "hello-world",
                options: FunctionInvokeOptions(
                  body: request
                )
              )

            print(response.message)
            """)

        CodeExample(
          code: """
            // Invoke without parameters
            let response = try await supabase
              .functions
              .invoke("hello-world")

            print(response)
            """)
      }

      Section("About Edge Functions") {
        VStack(alignment: .leading, spacing: 12) {
          FeaturePoint(
            icon: "bolt.fill",
            text: "Run server-side TypeScript/JavaScript code"
          )
          FeaturePoint(
            icon: "globe",
            text: "Deploy globally with low latency"
          )
          FeaturePoint(
            icon: "lock.fill",
            text: "Automatically authenticated with user session"
          )
          FeaturePoint(
            icon: "dollarsign.circle",
            text: "Pay only for what you use"
          )
        }
      }

      Section("Deployment") {
        CodeExample(
          code: """
            # Deploy a function
            supabase functions deploy hello-world

            # Invoke locally for testing
            supabase functions serve hello-world
            """)
      }
    }
    .navigationTitle("Edge Functions")
  }

  @MainActor
  func invokeHelloWorld() async {
    do {
      error = nil
      result = nil
      isLoading = true
      defer { isLoading = false }

      struct HelloWorldRequest: Encodable {
        let name: String
      }

      struct HelloWorldResponse: Decodable {
        let message: String
      }

      let request = HelloWorldRequest(name: name)

      let response: HelloWorldResponse = try await supabase.functions.invoke(
        "hello-world",
        options: FunctionInvokeOptions(body: request)
      )

      result = response.message
    } catch {
      self.error = error
    }
  }
}

struct FeaturePoint: View {
  let icon: String
  let text: String

  var body: some View {
    HStack(spacing: 12) {
      Image(systemName: icon)
        .foregroundColor(.accentColor)
        .frame(width: 24)
      Text(text)
        .font(.subheadline)
    }
  }
}
