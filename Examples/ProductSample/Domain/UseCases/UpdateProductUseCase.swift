//
//  UpdateProductUseCase.swift
//  ProductSample
//
//  Created by Guilherme Souza on 19/10/23.
//

import Foundation
import Supabase

protocol UpdateProductUseCase: UseCase<UpdateProductParams, Task<Void, Error>> {}

struct UpdateProductUseCaseImpl: UpdateProductUseCase {
  let productRepository: ProductRepository
  let productImageStorageRepository: any ProductImageStorageRepository

  func execute(input: UpdateProductParams) -> Task<Void, Error> {
    Task {
      var imageFilePath: String?

      if let image = input.image {
        imageFilePath = try await productImageStorageRepository.uploadImage(image)
      }

      try await productRepository.updateProduct(
        id: input.id, name: input.name, price: input.price, image: imageFilePath
      )
    }
  }
}
