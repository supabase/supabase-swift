//
//  WebAuthnPasskeysView.swift
//  Examples
//
//  Showcases the WebAuthn / passkey APIs: first-factor passkey sign-in & management,
//  and WebAuthn as a second factor (MFA). Drives the native AuthenticationServices UI.
//
//  Setup required to complete a real ceremony on-device:
//    1. Add your domain under `webcredentials:` in `Examples.entitlements` (Associated Domains)
//       and enable the capability for your signing team.
//    2. Host an `apple-app-site-association` file at that domain granting this app the
//       `webcredentials` service.
//    3. Configure `rp_id` in your Supabase project to match that domain.
//       The SDK reads rpId from the server response — no client-side configuration needed.
//

// WebAuthn/passkey APIs are experimental and live behind Auth's `Experimental` SPI.
@_spi(Experimental) import Auth
import AuthenticationServices
import Supabase
import SwiftUI

#if canImport(UIKit)
  import UIKit
#elseif canImport(AppKit)
  import AppKit
#endif

/// Returns a window to present the native passkey UI from.
@MainActor
private func webAuthnPresentationAnchor() -> ASPresentationAnchor {
  #if canImport(UIKit)
    return UIApplication.shared.firstKeyWindow ?? UIWindow()
  #elseif canImport(AppKit)
    return NSApplication.shared.keyWindow ?? NSWindow()
  #else
    return ASPresentationAnchor()
  #endif
}

/// Footer explaining the domain/entitlement setup passkeys need.
private struct WebAuthnSetupNote: View {
  var body: some View {
    Text(
      "Passkeys require an Associated Domains entitlement (webcredentials:<your-domain>) "
        + "and an apple-app-site-association file hosted at that domain. "
        + "The relying-party identifier is read from the server response automatically."
    )
    .font(.caption)
    .foregroundColor(.secondary)
  }
}

// MARK: - First-factor sign-in (signed-out)

struct SignInWithPasskeyView: View {
  @State private var error: Error?
  @State private var isLoading = false

  var body: some View {
    List {
      Section {
        Text(
          "Sign in with a passkey already registered for your account on this relying party. "
            + "Presents the native passkey sheet via AuthenticationServices and establishes a session."
        )
        .font(.subheadline)
        .foregroundColor(.secondary)
      }

      if isLoading {
        Section {
          ProgressView("Waiting for passkey…")
        }
      }

      if let error {
        Section {
          ErrorText(error)
        }
      }

      Section {
        Button {
          signIn()
        } label: {
          Label("Sign in with a passkey", systemImage: "person.badge.key.fill")
        }
        .disabled(isLoading)
      } footer: {
        WebAuthnSetupNote()
      }
    }
    .navigationTitle("Passkey Sign-In")
  }

  @MainActor
  private func signIn() {
    Task {
      do {
        error = nil
        isLoading = true
        defer { isLoading = false }

        // On success, AuthController observes authStateChanges and RootView switches to HomeView.
        try await supabase.auth.signInWithPasskey(
          presentationAnchor: webAuthnPresentationAnchor()
        )
      } catch {
        self.error = error
      }
    }
  }
}

// MARK: - Management (signed-in)

struct WebAuthnPasskeysView: View {
  @State private var passkeys: [PasskeyListItem] = []
  @State private var webAuthnFactors: [Factor] = []
  @State private var newFactorName = "My Passkey"
  @State private var error: Error?
  @State private var isLoading = false
  @State private var renameTarget: PasskeyListItem?
  @State private var renameText = ""

  var body: some View {
    List {
      Section {
        Text(
          "Register and manage passkeys for the signed-in user, and enroll WebAuthn as a second "
            + "factor. Each action drives the native passkey UI."
        )
        .font(.subheadline)
        .foregroundColor(.secondary)
      }

      if isLoading {
        Section {
          ProgressView("Working…")
        }
      }

      if let error {
        Section {
          ErrorText(error)
        }
      }

      Section("Passkeys") {
        Button {
          register()
        } label: {
          Label("Register a passkey", systemImage: "plus.circle.fill")
        }
        .disabled(isLoading)

        if passkeys.isEmpty {
          Text("No passkeys registered")
            .font(.caption)
            .foregroundColor(.secondary)
        } else {
          ForEach(passkeys) { passkey in
            VStack(alignment: .leading, spacing: 2) {
              Text(passkey.friendlyName ?? "Unnamed passkey")
                .font(.headline)
              Text("Created \(passkey.createdAt, style: .date)")
                .font(.caption)
                .foregroundColor(.secondary)
              if let lastUsedAt = passkey.lastUsedAt {
                Text("Last used \(lastUsedAt, style: .date)")
                  .font(.caption)
                  .foregroundColor(.secondary)
              }
              Text(passkey.id)
                .font(.system(.caption2, design: .monospaced))
                .foregroundColor(.secondary)
                .lineLimit(1)
            }
            .swipeActions {
              Button(role: .destructive) {
                delete(passkey)
              } label: {
                Label("Delete", systemImage: "trash")
              }

              Button {
                renameTarget = passkey
                renameText = passkey.friendlyName ?? ""
              } label: {
                Label("Rename", systemImage: "pencil")
              }
              .tint(.blue)
            }
          }
        }
      }

      Section {
        TextField("Factor name", text: $newFactorName)

        Button {
          enrollFactor()
        } label: {
          Label("Enroll WebAuthn factor", systemImage: "lock.shield.fill")
        }
        .disabled(newFactorName.isEmpty || isLoading)

        ForEach(webAuthnFactors) { factor in
          Button {
            verifyFactor(factor)
          } label: {
            HStack {
              Label(factor.friendlyName ?? "WebAuthn factor", systemImage: "checkmark.shield")
              Spacer()
              Text(factor.status.rawValue)
                .font(.caption)
                .foregroundColor(.secondary)
            }
          }
        }
      } header: {
        Text("WebAuthn MFA (second factor)")
      } footer: {
        WebAuthnSetupNote()
      }
    }
    .navigationTitle("WebAuthn & Passkeys")
    .task { await refresh() }
    .refreshable { await refresh() }
    .alert(
      "Rename passkey",
      isPresented: Binding(
        get: { renameTarget != nil },
        set: { if !$0 { renameTarget = nil } }
      )
    ) {
      TextField("Name", text: $renameText)
      Button("Cancel", role: .cancel) { renameTarget = nil }
      Button("Save") {
        if let target = renameTarget {
          rename(target, to: renameText)
        }
      }
    }
  }

  @MainActor
  private func refresh() async {
    do {
      error = nil
      isLoading = true
      defer { isLoading = false }

      passkeys = try await supabase.auth.listPasskeys()
      webAuthnFactors = try await supabase.auth.mfa.listFactors().webauthn
    } catch {
      self.error = error
    }
  }

  @MainActor
  private func register() {
    Task {
      do {
        error = nil
        isLoading = true
        defer { isLoading = false }

        _ = try await supabase.auth.registerPasskey(
          presentationAnchor: webAuthnPresentationAnchor()
        )
        await refresh()
      } catch {
        self.error = error
      }
    }
  }

  @MainActor
  private func delete(_ passkey: PasskeyListItem) {
    Task {
      do {
        error = nil
        try await supabase.auth.deletePasskey(id: passkey.id)
        await refresh()
      } catch {
        self.error = error
      }
    }
  }

  @MainActor
  private func rename(_ passkey: PasskeyListItem, to name: String) {
    renameTarget = nil
    Task {
      do {
        error = nil
        _ = try await supabase.auth.renamePasskey(id: passkey.id, friendlyName: name)
        await refresh()
      } catch {
        self.error = error
      }
    }
  }

  @MainActor
  private func enrollFactor() {
    Task {
      do {
        error = nil
        isLoading = true
        defer { isLoading = false }

        _ = try await supabase.auth.mfa.enrollWebAuthnFactor(
          friendlyName: newFactorName,
          presentationAnchor: webAuthnPresentationAnchor()
        )
        await refresh()
      } catch {
        self.error = error
      }
    }
  }

  @MainActor
  private func verifyFactor(_ factor: Factor) {
    Task {
      do {
        error = nil
        isLoading = true
        defer { isLoading = false }

        _ = try await supabase.auth.mfa.verifyWebAuthnFactor(
          factorId: factor.id,
          presentationAnchor: webAuthnPresentationAnchor()
        )
        await refresh()
      } catch {
        self.error = error
      }
    }
  }
}
