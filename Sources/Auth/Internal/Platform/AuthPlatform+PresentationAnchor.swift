//
//  AuthPlatform+PresentationAnchor.swift
//  Auth
//
//  Created by Guilherme Souza on 30/10/26.
//

#if canImport(AuthenticationServices) && !os(watchOS)
  import AuthenticationServices

  #if canImport(UIKit)
    import UIKit
  #elseif canImport(AppKit)
    import AppKit
  #endif

  extension AuthPlatform {
    /// The window a passkey sheet attaches to when the caller passes no anchor: the key window
    /// of the foreground scene, else any window of it, else a new one. The new window shows no
    /// sheet, so an app extension must pass an anchor.
    @MainActor
    static func defaultPresentationAnchor() -> ASPresentationAnchor {
      #if canImport(UIKit)
        guard !isAppExtension else { return ASPresentationAnchor() }
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let windows =
          (scenes.first { $0.activationState == .foregroundActive } ?? scenes.first)?.windows ?? []
        return windows.first(where: \.isKeyWindow) ?? windows.first ?? ASPresentationAnchor()
      #elseif canImport(AppKit)
        let app = NSApplication.shared
        return app.keyWindow ?? app.mainWindow ?? app.windows.first ?? ASPresentationAnchor()
      #endif
    }
  }
#endif
