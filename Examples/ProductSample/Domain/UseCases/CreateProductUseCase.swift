//
//  CreateProductUseCase.swift
//  ProductSample
//
//  Created by Guilherme Souza on 19/10/23.
//

import Foundation
import Supabase

protocol CreateProductUseCase: UseCase<CreateProductParams, Task<Void, Error>> {}

struct CreateProductUseCaseImpl: CreateProductUseCase {
  let productRepository: ProductRepository
  let productImageStorageRepository: ProductImageStorageRepository
  let authenticationRepository: AuthenticationRepository

  func execute(input: CreateProductParams) -> Task<Void, Error> {
    Task {
      let ownerID = try await authenticationRepository.currentUserID

      var imageFilePath: String?

      if let image = input.image {
        imageFilePath = try await productImageStorageRepository.uploadImage(image)
      }

      try await productRepository.createProduct(
        InsertProductDto(
          name: input.name, price: input.price, image: imageFilePath, ownerID: ownerID
        )
      )
    }
  }
}
