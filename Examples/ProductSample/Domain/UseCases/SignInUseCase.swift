//
//  SignInUseCase.swift
//  ProductSample
//
//  Created by Guilherme Souza on 20/10/23.
//

import Foundation

struct Credentials {
  let email, password: String
}

protocol SignInUseCase: UseCase<Credentials, Task<Void, Error>> {}

struct SignInUseCaseImpl: SignInUseCase {
  let repository: AuthenticationRepository

  func execute(input: Credentials) -> Task<(), Error> {
    Task {
      try await repository.signIn(email: input.email, password: input.password)
    }
  }
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
