//
//  SupabaseClient+SwiftUI.swift
//  Supabase
//
//  Created by Guilherme Souza on 14/11/26.
//

#if canImport(SwiftUI)
  import Foundation
  import IssueReporting
  public import SwiftUI

  extension EnvironmentValues {
    /// The ``SupabaseClient`` that views in this environment use.
    ///
    /// Set it once, near the root of the app, and read it in any view below:
    ///
    /// ```swift
    /// @main
    /// struct MyApp: App {
    ///   let supabase = try! SupabaseClient(supabaseURL: url, supabaseKey: key)
    ///
    ///   var body: some Scene {
    ///     WindowGroup {
    ///       RootView()
    ///         .environment(\.supabase, supabase)
    ///     }
    ///   }
    /// }
    ///
    /// struct ProfileView: View {
    ///   @Environment(\.supabase) private var supabase
    ///
    ///   var body: some View {
    ///     Button("Sign out") {
    ///       Task { try await supabase.auth.signOut() }
    ///     }
    ///   }
    /// }
    /// ```
    ///
    /// When no view above sets a client, the read returns a placeholder client for a local stack
    /// at `http://localhost:54321`, and the first such read reports an issue. The placeholder
    /// keeps its session in memory only and never refreshes it. Set the client on every root
    /// that starts a new environment, such as a `UIHostingController`.
    public var supabase: SupabaseClient {
      get { self[SupabaseClientKey.self] }
      set { self[SupabaseClientKey.self] = newValue }
    }
  }

  private enum SupabaseClientKey: EnvironmentKey {
    static var defaultValue: SupabaseClient { placeholder }

    /// Built, and reported, on the first read without a client. A missing client is one setup
    /// mistake, so it reports once, not on each render.
    private static let placeholder: SupabaseClient = {
      reportIssue(
        "No SupabaseClient in the SwiftUI environment. Set one with .environment(\\.supabase, client)."
      )
      // swift-format-ignore: NeverUseForceTry
      return try! SupabaseClient(
        supabaseURL: URL(string: "http://localhost:54321")!,
        supabaseKey: "sb_publishable_ACJWlzQHlZjBrEguHvfOxg_3BJgxAaH",
        configuration: .init(
          auth: .init(
            storage: InMemoryAuthStorage(),
            autoRefresh: .disabled,
            observesAppLifecycle: false
          )
        )
      )
    }()
  }
#endif
