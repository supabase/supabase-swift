//
//  Product.swift
//  ProductSample
//
//  Created by Guilherme Souza on 18/10/23.
//

import Foundation

import struct GoTrue.User

typealias UserID = User.ID

struct Product: Identifiable, Decodable {
  let id: String
  let name: String
  let price: Double
  let image: ImageKey?
}

struct ImageKey: RawRepresentable, Decodable {
  var rawValue: String
}

struct CreateProductParams {
  let name: String
  let price: Double
  let image: ImageUploadParams?
}

struct ImageUploadParams {
  let fileName: String
  let fileExtension: String?
  let mimeType: String?
  let data: Data
}

struct UpdateProductParams {
  var id: String
  var name: String?
  var price: Double?
  var image: ImageUploadParams?
}
