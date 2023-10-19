//
//  ProductDetailsViewModel.swift
//  ProductSample
//
//  Created by Guilherme Souza on 19/10/23.
//

import OSLog
import PhotosUI
import SwiftUI

@MainActor
final class ProductDetailsViewModel: ObservableObject {
  private let logger = Logger.make(category: "ProductDetailsViewModel")

  private let productId: Product.ID?

  private let updateProductUseCase: any UpdateProductUseCase
  private let createProductUseCase: any CreateProductUseCase
  private let getProductUseCase: any GetProductUseCase

  @Published var name: String = ""
  @Published var price: Double = 0
  @Published private var imageURL: URL?

  enum ImageSource {
    case remote(URL)
    case local(ProductImage)
  }

  var imageSource: ImageSource? {
    if case let .success(image) = self.image {
      return .local(image)
    }

    if let imageURL {
      return .remote(imageURL)
    }

    return nil
  }

  @Published var imageSelection: PhotosPickerItem? {
    didSet {
      if let imageSelection {
        Task {
          await loadTransferable(from: imageSelection)
        }
      }
    }
  }

  @Published private var image: Result<ProductImage, Error>?
  @Published var isSavingProduct = false

  let onCompletion: (Bool) -> Void

  init(
    updateProductUseCase: any UpdateProductUseCase = Dependencies.updateProductUseCase,
    createProductUseCase: any CreateProductUseCase = Dependencies.createProductUseCase,
    getProductUseCase: any GetProductUseCase = Dependencies.getProductUseCase,
    productId: Product.ID?,
    onCompletion: @escaping (Bool) -> Void
  ) {
    self.updateProductUseCase = updateProductUseCase
    self.createProductUseCase = createProductUseCase
    self.getProductUseCase = getProductUseCase
    self.productId = productId
    self.onCompletion = onCompletion
  }

  func loadProductIfNeeded() async {
    guard let productId else { return }

    do {
      let product = try await getProductUseCase.execute(input: productId).value
      name = product.name
      price = product.price

      if let image = product.image,
        let signedPath = try? await Dependencies.supabase.storage.from(id: "product-images")
          .createSignedURL(path: image, expiresIn: 3600).signedURL
      {

        imageURL = Dependencies.supabase.storage.configuration.url.appendingPathComponent(
          signedPath.path)
      }
    } catch {
      dump(error)
    }
  }

  func saveButtonTapped() async -> Bool {
    isSavingProduct = true
    defer { isSavingProduct = false }

    let imageUploadParams = image?.value.map { image in
      ImageUploadParams(
        fileName: UUID().uuidString,
        fileExtension: imageSelection?.supportedContentTypes.first?.preferredFilenameExtension,
        mimeType: imageSelection?.supportedContentTypes.first?.preferredMIMEType,
        data: image.data
      )
    }

    do {
      if let productId {
        logger.info("Will update product: \(productId)")

        try await updateProductUseCase.execute(
          input: UpdateProductParams(
            id: productId,
            name: name,
            price: price,
            image: imageUploadParams
          )
        ).value
      } else {
        logger.info("Will add product")
        try await createProductUseCase.execute(
          input: CreateProductParams(
            name: name,
            price: price,
            image: imageUploadParams
          )
        ).value
      }

      logger.error("Save succeeded")
      onCompletion(true)
      return true
    } catch {
      logger.error("Save failed: \(error)")
      onCompletion(false)
      return false
    }
  }

  private func loadTransferable(from imageSelection: PhotosPickerItem) async {
    do {
      let image = try await imageSelection.loadTransferable(type: ProductImage.self)
      self.image = image.map(Result.success)
    } catch {
      self.image = .failure(error)
    }
  }
}

struct ProductImage: Transferable {
  let image: Image
  let data: Data

  static var transferRepresentation: some TransferRepresentation {
    DataRepresentation(importedContentType: .image) { data in
      guard let uiImage = UIImage(data: data) else {
        throw TransferError.importFailed
      }

      let image = Image(uiImage: uiImage)
      return ProductImage(image: image, data: data)
    }
  }
}

enum TransferError: Error {
  case importFailed
}
