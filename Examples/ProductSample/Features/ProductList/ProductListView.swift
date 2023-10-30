//
//  ProductListView.swift
//  ProductSample
//
//  Created by Guilherme Souza on 19/10/23.
//

import SwiftUI

struct ProductListView: View {
  @ObservedObject var model: ProductListViewModel

  var body: some View {
    List {
      if let error = model.error {
        Text(error.localizedDescription)
          .frame(maxWidth: .infinity, alignment: .leading)
          .padding()
          .background(Color.red.opacity(0.5))
          .clipShape(RoundedRectangle(cornerRadius: 8))
          .padding()
          .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
          .listRowSeparator(.hidden)
      }

      ForEach(model.products) { product in
        NavigationLink(value: ProductDetailRoute(productId: product.id)) {
          LabeledContent(product.name, value: product.price.formatted(.currency(code: "USD")))
        }
      }
      .onDelete { indexSet in
        Task {
          await model.didSwipeToDelete(indexSet)
        }
      }
    }
    .listStyle(.plain)
    .overlay {
      if model.products.isEmpty {
        Text("Product list empty.")
      }
    }
    .task {
      await model.loadProducts()
    }
    .refreshable {
      await model.loadProducts()
    }
  }
}
