//
//  ExamplesApp.swift
//  Examples
//
//  Created by Guilherme Souza on 22/12/22.
//

import FacebookLogin
import GoogleSignIn
import Supabase
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

    ApplicationDelegate.shared.application(
      UIApplication.shared,
      open: url,
      sourceApplication: nil,
      annotation: [UIApplication.OpenURLOptionsKey.annotation]
    )
  }
}

@main
struct ExamplesApp: App {
  @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

  var body: some Scene {
    WindowGroup {
      RootView()
        .environment(AuthController())
        .onOpenURL {
          supabase.handle($0)
        }
    }
  }
}

// v3.0.0: Using convenience initializer for development environment
let supabase = SupabaseClient.development(
  supabaseURL: URL(string: SupabaseConfig["SUPABASE_URL"]!)!,
  supabaseKey: SupabaseConfig["SUPABASE_ANON_KEY"]!,
  options: .init(
    auth: .init(redirectToURL: Constants.redirectToURL),
    global: .init(
      logger: ConsoleLogger()
    )
  )
)

// Alternative: Traditional initialization (still supported)
// let supabase = SupabaseClient(
//   supabaseURL: URL(string: SupabaseConfig["SUPABASE_URL"]!)!,
//   supabaseKey: SupabaseConfig["SUPABASE_ANON_KEY"]!,
//   options: .init(
//     auth: .init(redirectToURL: Constants.redirectToURL),
//     global: .init(
//       logger: ConsoleLogger()
//     )
//   )
// )

struct ConsoleLogger: SupabaseLogger {
  func log(message: SupabaseLogMessage) {
    print(message)
  }
}
