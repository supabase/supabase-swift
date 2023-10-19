//
//  CreateProductUseCase.swift
//  ProductSample
//
//  Created by Guilherme Souza on 19/10/23.
//

import Foundation
import Supabase

struct CreateProductParams {
  let name: String
  let price: Double
  let image: ImageUploadParams?
}

protocol CreateProductUseCase: UseCase<CreateProductParams, Task<Void, Error>> {}

struct CreateProductUseCaseImpl: CreateProductUseCase {
  let repository: ProductRepository
  let imageUploadUseCase: any ImageUploadUseCase

  func execute(input: CreateProductParams) -> Task<(), Error> {
    Task {
      var imageFilePath: String?

      if let image = input.image {
        imageFilePath = try await imageUploadUseCase.execute(input: image).value
      }

      try await repository.createProduct(
        InsertProductDto(name: input.name, price: input.price, image: imageFilePath)
      )
    }
  }
}
