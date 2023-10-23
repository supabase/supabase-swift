//
//  Routes.swift
//  ProductSample
//
//  Created by Guilherme Souza on 21/10/23.
//

import Foundation

struct ProductDetailRoute: Hashable {
  let productId: Product.ID
}

struct AddProductRoute: Identifiable, Hashable {
  var id: AnyHashable { self }
}
