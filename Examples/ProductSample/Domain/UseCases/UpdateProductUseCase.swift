//
//  UpdateProductUseCase.swift
//  ProductSample
//
//  Created by Guilherme Souza on 19/10/23.
//

import Foundation
import Supabase

struct ImageUploadParams {
  let fileName: String
  let fileExtension: String?
  let mimeType: String?
  let data: Data
}

struct UpdateProductParams {
  var id: String
  var name: String?
  var price: Double?
  var image: ImageUploadParams?
}

protocol UpdateProductUseCase: UseCase<UpdateProductParams, Task<Void, Error>> {}

struct UpdateProductUseCaseImpl: UpdateProductUseCase {
  let productRepository: ProductRepository
  let productImageStorageRepository: any ProductImageStorageRepository

  func execute(input: UpdateProductParams) -> Task<(), Error> {
    Task {
      var imageFilePath: String?

      if let image = input.image {
        imageFilePath = try await productImageStorageRepository.uploadImage(image)
      }

      try await productRepository.updateProduct(
        id: input.id, name: input.name, price: input.price, image: imageFilePath)
    }
  }
}
