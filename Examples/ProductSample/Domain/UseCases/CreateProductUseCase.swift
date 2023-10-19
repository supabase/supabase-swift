//
//  CreateProductUseCase.swift
//  ProductSample
//
//  Created by Guilherme Souza on 19/10/23.
//

import Foundation

struct CreateProductParams: Encodable {
  let name: String
  let price: Double
  let image: String?
}

protocol CreateProductUseCase: UseCase<CreateProductParams, Result<Void, Error>> {}

struct CreateProductUseCaseImpl: CreateProductUseCase {
  let repository: ProductRepository

  func execute(input: CreateProductParams) async -> Result<(), Error> {
    do {
      try await repository.createProduct(input)
      return .success(())
    } catch {
      return .failure(error)
    }
  }
}
