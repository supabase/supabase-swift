//
//  ProductDetailsViewModel.swift
//  ProductSample
//
//  Created by Guilherme Souza on 19/10/23.
//

import SwiftUI

final class ProductDetailsViewModel: ObservableObject {
  private let productId: Product.ID?

  private let updateProductUseCase: any UpdateProductUseCase
  private let createProductUseCase: any CreateProductUseCase
  private let getProductUseCase: any GetProductUseCase

  @Published var name: String = ""
  @Published var price: Double = 0

  let onCompletion: (Bool) -> Void

  init(
    updateProductUseCase: any UpdateProductUseCase = UpdateProductUseCaseImpl(
      repository: ProductRepositoryImpl(supabase: supabase), storage: supabase.storage),
    createProductUseCase: any CreateProductUseCase = CreateProductUseCaseImpl(
      repository: ProductRepositoryImpl(supabase: supabase)),
    getProductUseCase: any GetProductUseCase = GetProductUseCaseImpl(
      repository: ProductRepositoryImpl(supabase: supabase)),
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

  func saveButtonTapped() async {
    let result: Result<Void, Error>

    if let productId {
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
      result = await createProductUseCase.execute(
        input: CreateProductParams(name: name, price: price, image: nil)
      )
    }

    switch result {
    case .failure(let error):
      dump(error)
      onCompletion(false)
    case .success:
      onCompletion(true)
    }
  }
}
