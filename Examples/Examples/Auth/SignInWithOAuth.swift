//
//  SignInWithOAuth.swift
//  Examples
//
//  Created by Guilherme Souza on 10/04/24.
//

import AuthenticationServices
import Supabase
import SwiftUI

struct SignInWithOAuth: View {
  let providers = Provider.allCases

  @State var provider = Provider.allCases[0]
  @Environment(\.webAuthenticationSession) var webAuthenticationSession

  var body: some View {
    VStack {
      Picker("Provider", selection: $provider) {
        ForEach(providers) { provider in
          Text("\(provider)").tag(provider)
        }
      }

      Button("Start Sign-in Flow") {
        Task {
          do {
            try await supabase.auth.signInWithOAuth(
              provider: provider,
              redirectTo: Constants.redirectToURL,
              launchFlow: { @MainActor url in
                try await webAuthenticationSession.authenticate(
                  using: url,
                  callbackURLScheme: Constants.redirectToURL.scheme!
                )
              }
            )
          } catch {
            debug("Failed to sign-in with OAuth flow: \(error)")
          }
        }
      }
    }
  }
}

#if canImport(UIKit)
  final class SignInWithOAuthViewController: UIViewController, UIPickerViewDataSource,
    UIPickerViewDelegate
  {
    let providers = Provider.allCases
    var provider = Provider.allCases[0]

    let providerPicker = UIPickerView()
    let signInButton = UIButton(type: .system)

    override func viewDidLoad() {
      super.viewDidLoad()
      setupViews()
    }

    func setupViews() {
      view.backgroundColor = .white

      providerPicker.dataSource = self
      providerPicker.delegate = self
      view.addSubview(providerPicker)
      providerPicker.translatesAutoresizingMaskIntoConstraints = false
      NSLayoutConstraint.activate([
        providerPicker.centerXAnchor.constraint(equalTo: view.centerXAnchor),
        providerPicker.centerYAnchor.constraint(equalTo: view.centerYAnchor),
        providerPicker.widthAnchor.constraint(equalToConstant: 200),
        providerPicker.heightAnchor.constraint(equalToConstant: 100),
      ])

      signInButton.setTitle("Start Sign-in Flow", for: .normal)
      signInButton.addTarget(self, action: #selector(signInButtonTapped), for: .touchUpInside)
      view.addSubview(signInButton)
      signInButton.translatesAutoresizingMaskIntoConstraints = false
      NSLayoutConstraint.activate([
        signInButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
        signInButton.topAnchor.constraint(equalTo: providerPicker.bottomAnchor, constant: 20),
      ])
    }

    @objc func signInButtonTapped() {
      Task {
        do {
          try await supabase.auth.signInWithOAuth(
            provider: provider,
            redirectTo: Constants.redirectToURL
          )
        } catch {
          debug("Failed to sign-in with OAuth flow: \(error)")
        }
      }
    }

    func numberOfComponents(in _: UIPickerView) -> Int {
      1
    }

    func pickerView(_: UIPickerView, numberOfRowsInComponent _: Int) -> Int {
      providers.count
    }

    func pickerView(_: UIPickerView, titleForRow row: Int, forComponent _: Int) -> String? {
      "\(providers[row])"
    }

    func pickerView(_: UIPickerView, didSelectRow row: Int, inComponent _: Int) {
      provider = providers[row]
    }
  }

  #Preview("UIKit") {
    SignInWithOAuthViewController()
  }

#endif

#Preview("SwiftUI") {
  SignInWithOAuth()
}
