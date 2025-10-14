//
//  RootView.swift
//  Examples
//
//  Created by Guilherme Souza on 22/12/22.
//

import Auth
import SwiftUI

struct RootView: View {
  @Environment(AuthController.self) var auth

  var body: some View {
    if auth.session == nil {
      NavigationStack {
        AuthExamplesView()
      }
    } else {
      HomeView()
    }
  }
}

struct ContentView_Previews: PreviewProvider {
  static var previews: some View {
    RootView()
  }
}
