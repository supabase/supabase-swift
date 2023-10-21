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
  static let productImageStorageRepository: ProductImageStorageRepository =
    ProductImageStorageRepositoryImpl(storage: supabase.storage)
  static let authenticationRepository: AuthenticationRepository = AuthenticationRepositoryImpl(
    client: supabase.auth
  )

  // MARK: Use Cases

  static let updateProductUseCase: any UpdateProductUseCase = UpdateProductUseCaseImpl(
    productRepository: productRepository,
    productImageStorageRepository: productImageStorageRepository
  )

  static let createProductUseCase: any CreateProductUseCase = CreateProductUseCaseImpl(
    productRepository: productRepository,
    productImageStorageRepository: productImageStorageRepository,
    authenticationRepository: authenticationRepository
  )

  static let getProductUseCase: any GetProductUseCase = GetProductUseCaseImpl(
    productRepository: productRepository
  )

  static let deleteProductUseCase: any DeleteProductUseCase = DeleteProductUseCaseImpl(
    repository: productRepository
  )

  static let getProductsUseCase: any GetProductsUseCase = GetProductsUseCaseImpl(
    repository: productRepository
  )

  static let signInUseCase: any SignInUseCase = SignInUseCaseImpl(
    repository: authenticationRepository
  )

  static let signUpUseCase: any SignUpUseCase = SignUpUseCaseImpl(
    repository: authenticationRepository
  )
}
