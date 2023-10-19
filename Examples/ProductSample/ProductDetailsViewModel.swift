//
//  ProductDetailsViewModel.swift
//  ProductSample
//
//  Created by Guilherme Souza on 19/10/23.
//

import OSLog
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

    switch await getProductUseCase.execute(input: productId) {
    case .success(let product):
      name = product.name
      price = product.price
    case .failure(let error):
      dump(error)
    }
  }

  func saveButtonTapped() async -> Bool {
    isSavingProduct = true
    defer { isSavingProduct = false }

    let result: Result<Void, Error>

    if let productId {
      logger.info("Will update product: \(productId)")
      result = await updateProductUseCase.execute(
        input: UpdateProductParams(
          id: productId,
          name: name,
          price: price,
          imageName: nil,
          imageFile: nil
        )
      )
    } else {
      logger.info("Will add product")
      result = await createProductUseCase.execute(
        input: CreateProductParams(name: name, price: price, image: nil)
      )
    }

    switch result {
    case .failure(let error):
      logger.error("Save failed: \(error)")
      onCompletion(false)
      return false
    case .success:
      logger.error("Save succeeded")
      onCompletion(true)
      return true
    }
  }
}
