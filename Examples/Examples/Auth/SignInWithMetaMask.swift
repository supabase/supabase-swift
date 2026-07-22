//
//  SignInWithMetaMask.swift
//  Examples
//
//  Demonstrates signing in with Supabase Auth using a Sign-In-With-Ethereum (SIWE) message
//  signed by the MetaMask wallet app
//

#if canImport(UIKit)

  import Auth
  @preconcurrency import metamask_ios_sdk
  import SwiftUI
  import UIKit

  @MainActor
  @Observable
  final class SignInWithMetaMaskController {
    enum State {
      case disconnected
      case notInstalled
      case connecting
      case connected(address: String, chainId: String)
      case signing
      case signedIn(Session)
    }

    static let appStoreURL = URL(
      string: "https://apps.apple.com/us/app/metamask-blockchain-wallet/id1438144202"
    )!

    var state: State = .disconnected
    var error: Error?

    private let metamaskSDK = MetaMaskSDK.shared(
      AppMetadata(name: "Supabase Examples", url: "https://supabase.com"),
      transport: .deeplinking(dappScheme: "com.supabase.swift-examples.metamask"),
      sdkOptions: nil
    )

    func handleOpenURL(_ url: URL) {
      guard url.host == "mmsdk" else { return }
      metamaskSDK.handleUrl(url)
    }

    func connect() async {
      error = nil

      guard let metamaskURL = URL(string: "metamask://"),
        UIApplication.shared.canOpenURL(metamaskURL)
      else {
        state = .notInstalled
        return
      }

      state = .connecting

      let result = await metamaskSDK.connect()

      switch result {
      case .success(let accounts):
        guard let address = accounts.first else {
          error = RequestError(from: ["code": -1, "message": "No accounts returned by MetaMask"])
          state = .disconnected
          return
        }
        state = .connected(address: address, chainId: metamaskSDK.chainId)
      case .failure(let requestError):
        error = requestError
        state = .disconnected
      }
    }

    func signIn() async {
      guard case .connected(let address, let chainId) = state else { return }

      error = nil
      state = .signing

      let message = siweMessage(address: address, chainId: chainId)
      let signRequest = EthereumRequest(method: .personalSign, params: [message, address])
      let signResult = await metamaskSDK.request(signRequest)

      switch signResult {
      case .success(let signature):
        do {
          let session = try await supabase.auth.signInWithWeb3(
            credentials: Web3Credentials(
              chain: .ethereum,
              message: message,
              signature: signature
            )
          )
          state = .signedIn(session)
        } catch {
          self.error = error
          state = .connected(address: address, chainId: chainId)
        }
      case .failure(let requestError):
        error = requestError
        state = .connected(address: address, chainId: chainId)
      }
    }

    private func siweMessage(address: String, chainId: String) -> String {
      let domain = "supabase.com"
      let nonce = String((0..<12).map { _ in "0123456789abcdef".randomElement()! })
      let issuedAt = ISO8601DateFormatter().string(from: Date())
      let decimalChainId = decimalChainId(from: chainId)
      return """
        \(domain) wants you to sign in with your Ethereum account:
        \(address)

        Sign in to the Supabase Examples app.

        URI: https://\(domain)
        Version: 1
        Chain ID: \(decimalChainId)
        Nonce: \(nonce)
        Issued At: \(issuedAt)
        """
    }

    private func decimalChainId(from chainId: String) -> String {
      if chainId.hasPrefix("0x"), let value = Int(chainId.dropFirst(2), radix: 16) {
        return String(value)
      }
      return chainId
    }
  }

  struct SignInWithMetaMaskView: View {
    @State private var controller = SignInWithMetaMaskController()

    var body: some View {
      List {
        Section {
          Text("Sign in with your Ethereum account using the MetaMask wallet app.")
            .font(.subheadline)
            .foregroundColor(.secondary)
        }

        switch controller.state {
        case .disconnected:
          Section {
            Button("Connect Wallet") {
              Task { await controller.connect() }
            }
          }

        case .notInstalled:
          Section {
            Text("MetaMask isn't installed on this device.")
              .foregroundColor(.secondary)
            Link("Install MetaMask", destination: SignInWithMetaMaskController.appStoreURL)
          }

        case .connecting:
          Section {
            ProgressView("Connecting to MetaMask...")
          }

        case .connected(let address, let chainId):
          Section("Connected") {
            Text(address).font(.footnote.monospaced())
            Text("Chain ID: \(chainId)").font(.caption).foregroundColor(.secondary)
          }
          Section {
            Button("Sign In") {
              Task { await controller.signIn() }
            }
          }

        case .signing:
          Section {
            ProgressView("Waiting for signature...")
          }

        case .signedIn(let session):
          Section("Signed In") {
            Text(session.user.id.uuidString).font(.footnote.monospaced())
          }
        }

        if let error = controller.error {
          Section {
            ErrorText(error)
          }
        }
      }
      .navigationTitle("Sign in with MetaMask")
      .onOpenURL { controller.handleOpenURL($0) }
    }
  }

  #Preview {
    NavigationStack {
      SignInWithMetaMaskView()
    }
  }

#endif
