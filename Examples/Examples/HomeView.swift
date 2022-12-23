//
//  HomeView.swift
//  Examples
//
//  Created by Guilherme Souza on 23/12/22.
//

import SwiftUI

struct HomeView: View {
  var body: some View {
    NavigationStack {
      Text("Hello, World!")
        .toolbar {
          ToolbarItem(placement: .cancellationAction) {
            Button("Sign out") {
              Task {
                try! await supabase.auth.signOut()
              }
            }
          }
        }
    }
  }
}

struct HomeView_Previews: PreviewProvider {
  static var previews: some View {
    HomeView()
  }
}
