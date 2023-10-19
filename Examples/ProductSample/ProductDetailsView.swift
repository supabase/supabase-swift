//
//  ProductDetailsView.swift
//  ProductSample
//
//  Created by Guilherme Souza on 19/10/23.
//

import SwiftUI

struct ProductDetailsView: View {
  @ObservedObject var model: ProductDetailsViewModel

  var body: some View {
    Form {
      Section {
        TextField("Product Name", text: $model.name)
        TextField("Product Price", value: $model.price, formatter: NumberFormatter())
      }
    }
    .toolbar {
      ToolbarItem(placement: .primaryAction) {
        Button("Save") {
          Task { await model.saveButtonTapped() }
        }
      }
    }
  }
}

#Preview {
  ProductDetailsView(model: ProductDetailsViewModel(productId: nil) { _ in })
}
