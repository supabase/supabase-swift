//
//  UseCase.swift
//  ProductSample
//
//  Created by Guilherme Souza on 19/10/23.
//

import Foundation
import Storage

protocol UseCase<Input, Output> {
  associatedtype Input
  associatedtype Output

  func execute(input: Input) async -> Output
}

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

struct UpdateProductParams {
  var id: String
  var name: String?
  var price: Double?

  var imageName: String?
  var imageFile: Data?
}

protocol UpdateProductUseCase: UseCase<UpdateProductParams, Result<Void, Error>> {}

struct UpdateProductUseCaseImpl: UpdateProductUseCase {
  let repository: ProductRepository

  // TODO: Abstract storage access
  let storage: SupabaseStorageClient

  func execute(input: UpdateProductParams) async -> Result<(), Error> {
    do {
      var image: String?

      if let imageName = input.imageName, let imageFile = input.imageFile, !imageFile.isEmpty {
        let filePath = "\(imageName).png"
        let imageFilePath = try await storage.from(id: "product-images")
          .upload(
            path: filePath,
            file: File(
              name: filePath, data: imageFile, fileName: filePath, contentType: "image/png"),
            fileOptions: FileOptions(contentType: "image/png", upsert: true)
          )

        image = buildImageURL(imageFilePath: imageFilePath)
      }

      try await repository.updateProduct(
        id: input.id, name: input.name, price: input.price, image: image)
      return .success(())
    } catch {
      return .failure(error)
    }
  }

  private func buildImageURL(imageFilePath: String) -> String {
    supabase.storage.configuration.url.appendingPathComponent("object/public/\(imageFilePath)")
      .absoluteString
  }
}

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
