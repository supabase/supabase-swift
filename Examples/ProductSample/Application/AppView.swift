//
//  AppView.swift
//  ProductSample
//
//  Created by Guilherme Souza on 18/10/23.
//

import SwiftUI

struct ProductDetailRoute: Hashable {
  let productId: String
}

struct AddProductRoute: Identifiable, Hashable {
  var id: AnyHashable { self }
}

@MainActor
final class AppViewModel: ObservableObject {
  let productListModel = ProductListViewModel()
  let authViewModel = AuthViewModel()

  enum AuthState {
    case authenticated
    case notAuthenticated
  }

  @Published var addProductRoute: AddProductRoute?
  @Published var authState: AuthState?

  func productDetailViewModel(with productId: String?) -> ProductDetailsViewModel {
    ProductDetailsViewModel(productId: productId) { [weak self] updated in
      Task {
        await self?.productListModel.loadProducts()
      }
    }
  }
}

struct AppView: View {
  @StateObject var model = AppViewModel()

  var body: some View {
    switch model.authState {
    case .authenticated:
      authenticatedView
    case .notAuthenticated:
      notAuthenticatedView
    case .none:
      ProgressView()
    }

  }

  var authenticatedView: some View {
    NavigationStack {
      ProductListView()
        .toolbar {
          ToolbarItem(placement: .primaryAction) {
            Button {
              model.addProductRoute = .init()
            } label: {
              Label("Add", systemImage: "plus")
            }
          }
        }
        .navigationDestination(for: ProductDetailRoute.self) { route in
          ProductDetailsView(model: model.productDetailViewModel(with: route.productId))
        }
    }
    .sheet(item: $model.addProductRoute) { _ in
      NavigationStack {
        ProductDetailsView(model: model.productDetailViewModel(with: nil))
      }
    }
  }

  var notAuthenticatedView: some View {
    AuthView(model: model.authViewModel)
  }
}

#Preview {
  AppView()
}
