//
//  AppView.swift
//  ProductSample
//
//  Created by Guilherme Souza on 18/10/23.
//

import OSLog
import SwiftUI

@MainActor
final class AppViewModel: ObservableObject {
  private let logger = Logger.make(category: "AppViewModel")
  private let authenticationRepository: AuthenticationRepository

  enum AuthState {
    case authenticated(ProductListViewModel)
    case notAuthenticated(AuthViewModel)
  }

  @Published var addProductRoute: AddProductRoute?
  @Published var authState: AuthState?

  private var authStateListenerTask: Task<Void, Never>?

  init(authenticationRepository: AuthenticationRepository = Dependencies.authenticationRepository) {
    self.authenticationRepository = authenticationRepository

    authStateListenerTask = Task {
      for await state in await authenticationRepository.authStateListener() {
        logger.debug("auth state changed: \(String(describing: state))")

        if Task.isCancelled {
          logger.debug("auth state task cancelled, returning.")
          return
        }

        self.authState =
          switch state
        {
        case .signedIn: .authenticated(.init())
        case .signedOut: .notAuthenticated(.init())
        }
      }
    }
  }

  deinit {
    authStateListenerTask?.cancel()
  }

  func productDetailViewModel(with productId: String?) -> ProductDetailsViewModel {
    ProductDetailsViewModel(productId: productId) { [weak self] _ in
      Task {
        if case let .authenticated(model) = self?.authState {
          await model.loadProducts()
        }
      }
    }
  }

  func signOutButtonTapped() async {
    await authenticationRepository.signOut()
  }
}

struct AppView: View {
  @StateObject var model = AppViewModel()

  var body: some View {
    switch model.authState {
    case let .authenticated(model):
      authenticatedView(model: model)
    case let .notAuthenticated(model):
      notAuthenticatedView(model: model)
    case .none:
      ProgressView()
    }
  }

  func authenticatedView(model: ProductListViewModel) -> some View {
    NavigationStack {
      ProductListView(model: model)
        .toolbar {
          ToolbarItem(placement: .cancellationAction) {
            Button("Sign out") {
              Task { await self.model.signOutButtonTapped() }
            }
          }
          ToolbarItem(placement: .primaryAction) {
            Button {
              self.model.addProductRoute = .init()
            } label: {
              Label("Add", systemImage: "plus")
            }
          }
        }
        .navigationDestination(for: ProductDetailRoute.self) { route in
          ProductDetailsView(model: self.model.productDetailViewModel(with: route.productId))
        }
    }
    .sheet(item: self.$model.addProductRoute) { _ in
      NavigationStack {
        ProductDetailsView(model: self.model.productDetailViewModel(with: nil))
      }
    }
  }

  func notAuthenticatedView(model: AuthViewModel) -> some View {
    AuthView(model: model)
  }
}
