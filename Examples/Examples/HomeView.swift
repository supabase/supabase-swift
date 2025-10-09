//
//  HomeView.swift
//  Examples
//
//  Created by Guilherme Souza on 23/12/22.
//

import Supabase
import SwiftUI

struct HomeView: View {
  @Environment(AuthController.self) var auth

  var body: some View {
    @Bindable var auth = auth

    TabView {
      // Database Tab
      NavigationStack {
        DatabaseExamplesView()
      }
      .tabItem {
        Label("Database", systemImage: "cylinder.split.1x2")
      }

      // Realtime Tab
      NavigationStack {
        RealtimeExamplesView()
      }
      .tabItem {
        Label("Realtime", systemImage: "bolt")
      }

      // Storage Tab
      NavigationStack {
        StorageExamplesView()
          .navigationDestination(for: Bucket.self, destination: BucketDetailView.init)
      }
      .tabItem {
        Label("Storage", systemImage: "externaldrive")
      }

      // Functions Tab
      NavigationStack {
        FunctionsExamplesView()
      }
      .tabItem {
        Label("Functions", systemImage: "function")
      }

      // Profile Tab
      ProfileView()
        .tabItem {
          Label("Profile", systemImage: "person.circle")
        }
    }
    .sheet(isPresented: $auth.isPasswordRecoveryFlow) {
      UpdatePasswordView()
    }
  }

  struct UpdatePasswordView: View {
    @Environment(\.dismiss) var dismiss

    @State var password: String = ""

    var body: some View {
      Form {
        SecureField("Password", text: $password)
          .textContentType(.newPassword)

        Button("Update password") {
          Task {
            do {
              try await supabase.auth.update(user: UserAttributes(password: password))
              dismiss()
            } catch {}
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
