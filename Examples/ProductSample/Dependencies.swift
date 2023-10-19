//
//  Dependencies.swift
//  ProductSample
//
//  Created by Guilherme Souza on 19/10/23.
//

import Foundation
import Supabase

enum Dependencies {
  static let supabase = SupabaseClient(
    supabaseURL: URL(string: Config.SUPABASE_URL)!,
    supabaseKey: Config.SUPABASE_ANON_KEY
  )

  // MARK: Repositories

  static let productRepository: ProductRepository = ProductRepositoryImpl(supabase: supabase)

  // MARK: Use Cases

  static let imageUploadUseCase: any ImageUploadUseCase = ImageUploadUseCaseImpl(
    storage: supabase.storage
  )

  static let updateProductUseCase: any UpdateProductUseCase = UpdateProductUseCaseImpl(
    repository: productRepository,
    imageUploadUseCase: imageUploadUseCase
  )

  static let createProductUseCase: any CreateProductUseCase = CreateProductUseCaseImpl(
    repository: productRepository,
    imageUploadUseCase: imageUploadUseCase
  )

  static let getProductUseCase: any GetProductUseCase = GetProductUseCaseImpl(
    repository: productRepository
  )
}
