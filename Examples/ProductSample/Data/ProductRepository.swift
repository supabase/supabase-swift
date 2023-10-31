//
//  ProductRepository.swift
//  ProductSample
//
//  Created by Guilherme Souza on 18/10/23.
//

import Foundation
import Supabase

struct InsertProductDto: Encodable {
  let name: String
  let price: Double
  let image: String?
  let ownerID: UserID

  enum CodingKeys: String, CodingKey {
    case name
    case price
    case image
    case ownerID = "owner_id"
  }
}

protocol ProductRepository: Sendable {
  func createProduct(_ product: InsertProductDto) async throws
  func getProducts() async throws -> [Product]
  func getProduct(id: Product.ID) async throws -> Product
  func deleteProduct(id: Product.ID) async throws
  func updateProduct(id: String, name: String?, price: Double?, image: String?) async throws
}

struct ProductRepositoryImpl: ProductRepository {
  let supabase: SupabaseClient

  func createProduct(_ product: InsertProductDto) async throws {
    try await supabase.database.from("products").insert(values: product).execute()
  }

  func getProducts() async throws -> [Product] {
    try await supabase.database.from("products").select().execute().value
  }

  func getProduct(id: Product.ID) async throws -> Product {
    try await supabase.database.from("products").select().eq(column: "id", value: id).single()
      .execute().value
  }

  func deleteProduct(id: Product.ID) async throws {
    try await supabase.database.from("products").delete().eq(column: "id", value: id).execute()
      .value
  }

  func updateProduct(id: String, name: String?, price: Double?, image: String?) async throws {
    var params: [String: AnyJSON] = [:]

    if let name {
      params["name"] = .string(name)
    }

    if let price {
      params["price"] = .number(price)
    }

    if let image {
      params["image"] = .string(image)
    }

    if params.isEmpty {
      // nothing to update, just return.
      return
    }

    try await supabase.database.from("products")
      .update(values: params)
      .eq(column: "id", value: id)
      .execute()
  }
}
