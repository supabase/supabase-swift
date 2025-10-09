//
//  ProfileView.swift
//  UserManagement
//
//  Created by Guilherme Souza on 17/11/23.
//

import PhotosUI
import Supabase
import SwiftUI

@MainActor
struct ProfileView: View {
  @State var username = ""
  @State var fullName = ""
  @State var website = ""

  @State var isLoading = false

  @State var imageSelection: PhotosPickerItem?
  @State var avatarImage: AvatarImage?

  var body: some View {
    NavigationStack {
      Form {
        Section {
          HStack {
            Group {
              if let avatarImage {
                avatarImage.image.resizable()
              } else {
                Color.clear
              }
            }
            .scaledToFit()
            .frame(width: 80, height: 80)

            Spacer()

            PhotosPicker(selection: $imageSelection, matching: .images) {
              Image(systemName: "pencil.circle.fill")
                .symbolRenderingMode(.multicolor)
                .font(.system(size: 30))
                .foregroundColor(.accentColor)
            }
          }
        }

        Section {
          TextField("Username", text: $username)
            .textContentType(.username)
            #if os(iOS)
              .textInputAutocapitalization(.never)
            #endif
          TextField("Full name", text: $fullName)
            .textContentType(.name)
          TextField("Website", text: $website)
            .textContentType(.URL)
            #if os(iOS)
              .textInputAutocapitalization(.never)
            #endif
        }

        Section {
          Button("Update profile") {
            updateProfileButtonTapped()
          }
          .bold()

          if isLoading {
            ProgressView()
          }

          Button("Delete account", role: .destructive) {
            deleteAccountButtonTapped()
          }
        }
      }
      .onMac { $0.padding() }
      .navigationTitle("Profile")
      .toolbar(content: {
        ToolbarItem {
          Button("Sign out", role: .destructive) {
            Task {
              try? await supabase.auth.signOut()
            }
          }
        }
      })
      .onChange(of: imageSelection) { _, newValue in
        guard let newValue else { return }
        loadTransferable(from: newValue)
      }
    }
    .task {
      await getInitialProfile()
    }
  }

  func getInitialProfile() async {
    do {
      let currentUser = try await supabase.auth.session.user

      let profile: Profile = try await supabase.from("profiles")
        .select()
        .eq("id", value: currentUser.id)
        .single()
        .execute()
        .value

      username = profile.username ?? ""
      fullName = profile.fullName ?? ""
      website = profile.website ?? ""

      if let avatarURL = profile.avatarURL, !avatarURL.isEmpty {
        try await downloadImage(path: avatarURL)
      }

    } catch {
      debugPrint(error)
    }
  }

  func updateProfileButtonTapped() {
    Task {
      isLoading = true
      defer { isLoading = false }
      do {
        let imageURL = try await uploadImage()

        let currentUser = try await supabase.auth.session.user

        let updatedProfile = Profile(
          username: username,
          fullName: fullName,
          website: website,
          avatarURL: imageURL
        )

        try await supabase
          .from("profiles")
          .update(updatedProfile)
          .eq("id", value: currentUser.id)
          .execute()
      } catch {
        debugPrint(error)
      }
    }
  }

  private func loadTransferable(from imageSelection: PhotosPickerItem) {
    Task {
      do {
        avatarImage = try await imageSelection.loadTransferable(type: AvatarImage.self)
      } catch {
        debugPrint(error)
      }
    }
  }

  private func downloadImage(path: String) async throws {
    let data = try await supabase.storage.from("avatars").download(path: path)
    avatarImage = AvatarImage(data: data)
  }

  private func uploadImage() async throws -> String? {
    guard let data = avatarImage?.data else { return nil }

    let userId = try await supabase.auth.session.user.id.uuidString
    let filePath = "\(userId)/profile.jpeg"

    try await supabase.storage
      .from("avatars")
      .upload(
        path: filePath,
        file: data,
        options: FileOptions(contentType: "image/jpeg", upsert: true)
      )

    return filePath
  }

  private func deleteAccountButtonTapped() {
    Task {
      do {
        let currentUserId = try await supabase.auth.session.user.id
        try await supabase.auth.admin.deleteUser(
          id: currentUserId,
          shouldSoftDelete: true
        )
      } catch {
        debugPrint(error)
      }
    }
  }
}

#Preview {
  ProfileView()
}
