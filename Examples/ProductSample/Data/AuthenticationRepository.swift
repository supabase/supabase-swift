//
//  AuthenticationRepository.swift
//  ProductSample
//
//  Created by Guilherme Souza on 19/10/23.
//

import Foundation
import Supabase

protocol AuthenticationRepository {
  var authStateListener: AsyncStream<AuthenticationState> { get }

  var currentUserID: UUID { get async throws }

  func signIn(email: String, password: String) async throws
  func signUp(email: String, password: String) async throws -> SignUpResult
  func signInWithApple() async throws
  func signOut() async
}

struct AuthenticationRepositoryImpl: AuthenticationRepository {
  let client: GoTrueClient

  init(client: GoTrueClient) {
    self.client = client

    let (stream, continuation) = AsyncStream.makeStream(of: AuthenticationState.self)
    let handle = client.addAuthStateChangeListener { event in
      let state: AuthenticationState? =
        switch event {
        case .signedIn: AuthenticationState.signedIn
        case .signedOut: AuthenticationState.signedOut
        case .passwordRecovery, .tokenRefreshed, .userUpdated, .userDeleted: nil
        }

      if let state {
        continuation.yield(state)
      }
    }

    continuation.onTermination = { _ in
      client.removeAuthStateChangeListener(handle)
    }

    self.authStateListener = stream
  }

  let authStateListener: AsyncStream<AuthenticationState>

  var currentUserID: UUID {
    get async throws {
      try await client.session.user.id
    }
  }

  func signIn(email: String, password: String) async throws {
    try await client.signIn(email: email, password: password)
  }

  func signUp(email: String, password: String) async throws -> SignUpResult {
    let response = try await client.signUp(
      email: email,
      password: password,
      redirectTo: URL(string: "dev.grds.ProductSample://")
    )
    if case .session = response {
      return .success
    }
    return .requiresConfirmation
  }

  func signInWithApple() async throws {
    fatalError("\(#function) unimplemented")
  }

  func signOut() async {
    try? await client.signOut()
  }
}
