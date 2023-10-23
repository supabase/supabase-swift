//
//  SignUpUseCase.swift
//  ProductSample
//
//  Created by Guilherme Souza on 21/10/23.
//

import Foundation

enum SignUpResult {
  case success
  case requiresConfirmation
}

protocol SignUpUseCase: UseCase<Credentials, Task<SignUpResult, Error>> {}

struct SignUpUseCaseImpl: SignUpUseCase {
  let repository: AuthenticationRepository

  func execute(input: Credentials) -> Task<SignUpResult, Error> {
    Task {
      try await repository.signUp(email: input.email, password: input.password)
    }
  }
}
