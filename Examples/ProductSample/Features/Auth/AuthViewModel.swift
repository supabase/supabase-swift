//
//  AuthViewModel.swift
//  ProductSample
//
//  Created by Guilherme Souza on 19/10/23.
//

import Foundation
import OSLog

@MainActor
final class AuthViewModel: ObservableObject {
  private let logger = Logger.make(category: "AuthViewModel")

  private let signInUseCase: any SignInUseCase
  private let signUpUseCase: any SignUpUseCase

  @Published var email = ""
  @Published var password = ""

  enum Status {
    case loading
    case requiresConfirmation
    case error(Error)
  }

  @Published var status: Status?

  init(
    signInUseCase: any SignInUseCase = Dependencies.signInUseCase,
    signUpUseCase: any SignUpUseCase = Dependencies.signUpUseCase
  ) {
    self.signInUseCase = signInUseCase
    self.signUpUseCase = signUpUseCase
  }

  func signInButtonTapped() async {
    status = .loading
    do {
      try await signInUseCase.execute(input: .init(email: email, password: password)).value
      status = nil
    } catch {
      status = .error(error)
      logger.error("Error signing in: \(error)")
    }
  }

  func signUpButtonTapped() async {
    status = .loading
    do {
      let result = try await signUpUseCase.execute(input: .init(email: email, password: password))
        .value
      if result == .requiresConfirmation {
        status = .requiresConfirmation
      } else {
        status = nil
      }
    } catch {
      status = .error(error)
      logger.error("Error signing up: \(error)")
    }
  }

  func signInWithAppleButtonTapped() async {}

  func onOpenURL(_ url: URL) async {
    status = .loading

    do {
      logger.debug("Retrieve session from url: \(url)")
      try await Dependencies.supabase.auth.session(from: url)
      await signInButtonTapped()
      status = nil
    } catch {
      status = .error(error)
      logger.error("Error creating session from url: \(error)")
    }
  }
}
