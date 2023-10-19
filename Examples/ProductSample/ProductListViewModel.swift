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
  private let productRepository: ProductRepository

  @Published var products: [Product] = []
  @Published var isLoading = false
  @Published var error: Error?

  init(productRepository: ProductRepository = Dependencies.productRepository) {
    self.productRepository = productRepository
  }

  func loadProducts() async {
    isLoading = true
    defer { isLoading = false }

    do {
      products = try await productRepository.getProducts()
      logger.info("Products loaded.")
      self.error = nil
    } catch {
      logger.error("Error loading products: \(error)")
      self.error = error
    }
  }

  func removeItem(product: Product) async {
    self.products.removeAll { $0.id == product.id }

    do {
      try await productRepository.deleteProduct(id: product.id)
      self.error = nil
    } catch {
      self.error = error
    }

    await loadProducts()
  }
}
