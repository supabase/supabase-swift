//
//  ExamplesApp.swift
//  Examples
//
//  Created by Guilherme Souza on 22/12/22.
//

import FacebookLogin
import GoogleSignIn
@_spi(Experimental) import Supabase
import SwiftUI
import UIKit

final class AppDelegate: UIResponder, UIApplicationDelegate {
  func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
  ) -> Bool {
    ApplicationDelegate.shared.application(
      application,
      didFinishLaunchingWithOptions: launchOptions
    )
  }

  func application(
    _ application: UIApplication,
    configurationForConnecting connectingSceneSession: UISceneSession,
    options: UIScene.ConnectionOptions
  ) -> UISceneConfiguration {
    let sceneConfig = UISceneConfiguration(
      name: "Default Configuration",
      sessionRole: connectingSceneSession.role
    )
    sceneConfig.delegateClass = SceneDelegate.self
    return sceneConfig
  }
}

final class SceneDelegate: UIResponder, UIWindowSceneDelegate {
  func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
    guard let url = URLContexts.first?.url else { return }

    Task {
      guard await !supabaseClient.auth.isAuthRedirect(url) else { return }

      ApplicationDelegate.shared.application(
        UIApplication.shared,
        open: url,
        sourceApplication: nil,
        annotation: [UIApplication.OpenURLOptionsKey.annotation]
      )
    }
  }
}

@main
struct ExamplesApp: App {
  @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

  @State private var auth = AuthModel(client: supabaseClient.auth)

  var body: some Scene {
    WindowGroup {
      RootView()
        .environment(\.supabase, supabaseClient)
        .environment(auth)
        .task {
          do {
            for outcome in try await supabaseClient.storage.resumableUploads.resumeAll() {
              if let error = outcome.error {
                print("Resumable upload \(outcome.upload.path) did not resume: \(error)")
              }
            }
          } catch {
            print("Resumable uploads could not be read: \(error)")
          }
        }
    }
  }
}

// swift-format-ignore: NeverUseForceTry
let supabaseClient = try! SupabaseClient(
  supabaseURL: URL(string: SupabaseConfig["SUPABASE_URL"]!)!,
  supabaseKey: (SupabaseConfig["SUPABASE_PUBLISHABLE_KEY"] ?? SupabaseConfig["SUPABASE_ANON_KEY"])!,
  configuration: .init(
    auth: .init(redirectTo: Constants.redirectToURL)
  )
)
