//
//  ProductListViewModel.swift
//  ProductSample
//
//  Created by Guilherme Souza on 19/10/23.
//

import SwiftUI

@MainActor
final class ProductListViewModel: ObservableObject {
  let productRepository: ProductRepository

  @Published var products: [Product] = []
  @Published var isLoading = false
  @Published var error: Error?

  init(productRepository: ProductRepository = ProductRepositoryImpl(supabase: supabase)) {
    self.productRepository = productRepository
  }

  func loadProducts() async {
    isLoading = true
    defer { isLoading = false }

    do {
      products = try await productRepository.getProducts()
      self.error = nil
    } catch {
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
