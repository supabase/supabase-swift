//
//  SupabaseClient+UIApplicationDelegate.swift
//
//
//  Created by Guilherme Souza on 15/05/24.
//

import UIKit

extension SupabaseClient {
  @discardableResult
  public func application(
    _: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    if let url = launchOptions?[.url] as? URL {
      handleDeepLink(url)
    }

    return true
  }

  public func application(
    _: UIApplication,
    open url: URL,
    options _: [UIApplication.OpenURLOptionsKey: Any] = [:]
  ) -> Bool {
    handleDeepLink(url)
    return true
  }

  @MainActor
  public func scene(_: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
    guard let url = URLContexts.first?.url else { return }

    handleDeepLink(url)
  }

  private func handleDeepLink(_ url: URL) {
    let logger = options.global.logger

    Task {
      do {
        try await auth.session(from: url)
      } catch {
        logger?.error(
          """
          Failure loading session.
          URL: \(url.absoluteString)
          Error: \(error)
          """
        )
      }
    }
  }
}
