//
//  ProductListViewModel.swift
//  ProductSample
//
//  Created by Guilherme Souza on 19/10/23.
//

import OSLog
import SwiftUI

@MainActor
final class ProductListViewModel: ObservableObject {
  private let logger = Logger.make(category: "ProductListViewModel")

  private let deleteProductUseCase: any DeleteProductUseCase
  private let getProductsUseCase: any GetProductsUseCase

  @Published var products: [Product] = []
  @Published var isLoading = false
  @Published var error: Error?

  init(
    deleteProductUseCase: any DeleteProductUseCase = Dependencies.deleteProductUseCase,
    getProductsUseCase: any GetProductsUseCase = Dependencies.getProductsUseCase
  ) {
    self.deleteProductUseCase = deleteProductUseCase
    self.getProductsUseCase = getProductsUseCase
  }

  func loadProducts() async {
    isLoading = true
    defer { isLoading = false }

    do {
      products = try await getProductsUseCase.execute().value
      logger.info("Products loaded.")
      error = nil
    } catch {
      logger.error("Error loading products: \(error)")
      self.error = error
    }
  }

  func didSwipeToDelete(_ indexes: IndexSet) async {
    for index in indexes {
      let product = products[index]
      await removeItem(product: product)
    }
  }

  private func removeItem(product: Product) async {
    products.removeAll { $0.id == product.id }

    do {
      try await deleteProductUseCase.execute(input: product.id).value
      error = nil
    } catch {
      logger.error("Failed to remove product: \(product.id) error: \(error)")
      self.error = error
    }

    await loadProducts()
  }
}
