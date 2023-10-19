//
//  GetProductUseCase.swift
//  ProductSample
//
//  Created by Guilherme Souza on 19/10/23.
//

import Foundation

protocol GetProductUseCase: UseCase<Product.ID, Result<Product, Error>> {}

struct GetProductUseCaseImpl: GetProductUseCase {
  let repository: ProductRepository

  func execute(input: Product.ID) async -> Result<Product, Error> {
    do {
      let product = try await repository.getProduct(id: input)
      return .success(product)
    } catch {
      return .failure(error)
    }
  }
}
