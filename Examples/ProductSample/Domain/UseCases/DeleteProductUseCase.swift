//
//  DeleteProductUseCase.swift
//  ProductSample
//
//  Created by Guilherme Souza on 19/10/23.
//

import Foundation

protocol DeleteProductUseCase: UseCase<Product.ID, Task<Void, Error>> {}

struct DeleteProductUseCaseImpl: DeleteProductUseCase {
  let repository: ProductRepository

  func execute(input: Product.ID) -> Task<Void, Error> {
    Task {
      try await repository.deleteProduct(id: input)
    }
  }
}
