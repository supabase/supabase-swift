//
//  HomeView.swift
//  Examples
//
//  Created by Guilherme Souza on 23/12/22.
//

import Supabase
import SwiftUI

struct HomeView: View {
  var body: some View {
    TabView {
      NavigationStack {
        DatabaseExamplesView()
      }
      .tabItem {
        Label("Database", systemImage: "cylinder.split.1x2")
      }

      NavigationStack {
        RealtimeExamplesView()
      }
      .tabItem {
        Label("Realtime", systemImage: "bolt")
      }

      NavigationStack {
        StorageExamplesView()
          .navigationDestination(for: Bucket.self, destination: BucketDetailView.init)
      }
      .tabItem {
        Label("Storage", systemImage: "externaldrive")
      }

      NavigationStack {
        FunctionsExamplesView()
      }
      .tabItem {
        Label("Functions", systemImage: "function")
      }

      ProfileView()
        .tabItem {
          Label("Profile", systemImage: "person.circle")
        }
    }
  }
}

struct HomeView_Previews: PreviewProvider {
  static var previews: some View {
    HomeView()
  }
}
