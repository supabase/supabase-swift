//
//  GetProductsUseCase.swift
//  ProductSample
//
//  Created by Guilherme Souza on 19/10/23.
//

import Foundation

protocol GetProductsUseCase: UseCase<Void, Task<[Product], Error>> {}

struct GetProductsUseCaseImpl: GetProductsUseCase {
  let repository: any ProductRepository

  func execute(input: ()) -> Task<[Product], Error> {
    Task {
      try await repository.getProducts()
    }
  }
}
