//
//  AuthView.swift
//  ProductSample
//
//  Created by Guilherme Souza on 19/10/23.
//

import SwiftUI

struct AuthView: View {
  @ObservedObject var model: AuthViewModel

  var body: some View {
    Text("Hello, World!")
  }
}

#Preview {
  AuthView(model: AuthViewModel())
}
