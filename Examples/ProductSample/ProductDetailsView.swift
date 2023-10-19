//
//  ProductDetailsView.swift
//  ProductSample
//
//  Created by Guilherme Souza on 19/10/23.
//

import SwiftUI

struct ProductDetailsView: View {
  @ObservedObject var model: ProductDetailsViewModel

  @Environment(\.dismiss) private var dismiss

  var body: some View {
    Form {
      Section {
        TextField("Product Name", text: $model.name)
        TextField("Product Price", value: $model.price, formatter: NumberFormatter())
      }
    }
    .task { await model.loadProductIfNeeded() }
    .toolbar {
      ToolbarItem(placement: .primaryAction) {
        if model.isSavingProduct {
          ProgressView()
        } else {
          Button("Save") {
            Task {
              if await model.saveButtonTapped() {
                dismiss()
              }
            }
          }
        }
      }
    }
  }
}

#Preview {
  ProductDetailsView(model: ProductDetailsViewModel(productId: nil) { _ in })
}
