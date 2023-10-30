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
  private let productImageStorage: ProductImageStorageRepository

  @Published var name: String = ""
  @Published var price: Double = 0

  enum ImageSource {
    case remote(ProductImage)
    case local(ProductImage)

    var productImage: ProductImage {
      switch self {
      case let .remote(image), let .local(image): image
      }
    }
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

  @Published var imageSource: ImageSource?
  @Published var isSavingProduct = false

  let onCompletion: (Bool) -> Void

  init(
    updateProductUseCase: any UpdateProductUseCase = Dependencies.updateProductUseCase,
    createProductUseCase: any CreateProductUseCase = Dependencies.createProductUseCase,
    getProductUseCase: any GetProductUseCase = Dependencies.getProductUseCase,
    productImageStorage: ProductImageStorageRepository = Dependencies.productImageStorageRepository,
    productId: Product.ID?,
    onCompletion: @escaping (Bool) -> Void
  ) {
    self.updateProductUseCase = updateProductUseCase
    self.createProductUseCase = createProductUseCase
    self.getProductUseCase = getProductUseCase
    self.productImageStorage = productImageStorage
    self.productId = productId
    self.onCompletion = onCompletion
  }

  func loadProductIfNeeded() async {
    guard let productId else { return }

    do {
      let product = try await getProductUseCase.execute(input: productId).value
      name = product.name
      price = product.price

      if let image = product.image {
        let data = try await productImageStorage.downloadImage(image)
        imageSource = ProductImage(data: data).map(ImageSource.remote)
      }
    } catch {
      logger.error("Error loading product: \(error)")
    }
  }

  func saveButtonTapped() async -> Bool {
    isSavingProduct = true
    defer { isSavingProduct = false }

    let imageUploadParams =
      if case let .local(image) = imageSource
    {
      ImageUploadParams(
        fileName: UUID().uuidString,
        fileExtension: imageSelection?.supportedContentTypes.first?.preferredFilenameExtension,
        mimeType: imageSelection?.supportedContentTypes.first?.preferredMIMEType,
        data: image.data
      )
    } else {
      ImageUploadParams?.none
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
    if let image = try? await imageSelection.loadTransferable(type: ProductImage.self) {
      imageSource = .local(image)
    }
  }
}

struct ProductImage: Transferable {
  let image: Image
  let data: Data

  static var transferRepresentation: some TransferRepresentation {
    DataRepresentation(importedContentType: .image) { data in
      guard let image = ProductImage(data: data) else {
        throw TransferError.importFailed
      }

      return image
    }
  }
}

extension ProductImage {
  init?(data: Data) {
    guard let uiImage = UIImage(data: data) else {
      return nil
    }

    let image = Image(uiImage: uiImage)
    self.init(image: image, data: data)
  }
}

enum TransferError: Error {
  case importFailed
}
