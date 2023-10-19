//
//  GetProductUseCase.swift
//  ProductSample
//
//  Created by Guilherme Souza on 19/10/23.
//

import Foundation

protocol GetProductUseCase: UseCase<Product.ID, Task<Product, Error>> {}

struct GetProductUseCaseImpl: GetProductUseCase {
  let repository: ProductRepository

  func execute(input: Product.ID) -> Task<Product, Error> {
    Task {
      try await repository.getProduct(id: input)
    }
  }
}
