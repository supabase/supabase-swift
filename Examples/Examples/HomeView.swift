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

  @State private var mfaStatus: MFAStatus?

  var body: some View {
    @Bindable var auth = auth

    TabView {
      ProfileView()
        .tabItem {
          Label("Profile", systemImage: "person.circle")
        }

      NavigationStack {
        BucketList()
          .navigationDestination(for: Bucket.self, destination: BucketDetailView.init)
      }
      .tabItem {
        Label("Storage", systemImage: "externaldrive")
      }
    }
    .sheet(isPresented: $auth.isPasswordRecoveryFlow) {
      UpdatePasswordView()
    }
  }

  private func verifyMFAStatus() async -> MFAStatus? {
    do {
      let aal = try await supabase.auth.mfa.getAuthenticatorAssuranceLevel()
      switch (aal.currentLevel, aal.nextLevel) {
      case ("aal1", "aal1"):
        return .unenrolled
      case ("aal1", "aal2"):
        return .unverified
      case ("aal2", "aal2"):
        return .verified
      case ("aal2", "aal1"):
        return .disabled
      default:
        return nil
      }
    } catch {
      return nil
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
