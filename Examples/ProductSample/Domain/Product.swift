//
//  Product.swift
//  ProductSample
//
//  Created by Guilherme Souza on 18/10/23.
//

import Foundation

struct Product: Identifiable, Decodable {
  let id: String
  let name: String
  let price: Double
  let image: ImageKey?
}

struct ImageKey: RawRepresentable, Decodable {
  var rawValue: String
}
