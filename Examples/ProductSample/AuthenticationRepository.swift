//
//  AuthenticationRepository.swift
//  ProductSample
//
//  Created by Guilherme Souza on 19/10/23.
//

import Foundation
import Supabase

protocol AuthenticationRepository {
  func signIn(email: String, password: String) async throws
  func signUp(email: String, password: String) async throws
  func signInWithApple() async throws
}

struct AuthenticationRepositoryImpl: AuthenticationRepository {
  let client: GoTrueClient

  func signIn(email: String, password: String) async throws {
    try await client.signIn(email: email, password: password)
  }

  func signUp(email: String, password: String) async throws {
    try await client.signUp(email: email, password: password)
  }

  func signInWithApple() async throws {
    fatalError("\(#function) unimplemented")
  }
}
