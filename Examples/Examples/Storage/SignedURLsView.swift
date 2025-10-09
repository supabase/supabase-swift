//
//  SignedURLsView.swift
//  Examples
//
//  Demonstrates signed URLs for temporary file access
//

import Supabase
import SwiftUI

struct SignedURLsView: View {
  @State private var selectedBucket = ""
  @State private var buckets: [Bucket] = []
  @State private var filePath = ""
  @State private var expiresIn = "3600"  // 1 hour
  @State private var signedURL: URL?
  @State private var signedUploadURL: SignedUploadURL?
  @State private var publicURL: URL?
  @State private var error: Error?
  @State private var isLoading = false

  var body: some View {
    List {
      Section {
        Text("Generate temporary URLs for secure file access and uploads")
          .font(.caption)
          .foregroundColor(.secondary)
      }

      Section("File Selection") {
        if buckets.isEmpty {
          Text("Loading buckets...")
            .foregroundColor(.secondary)
        } else {
          Picker("Bucket", selection: $selectedBucket) {
            Text("Select a bucket").tag("")
            ForEach(buckets) { bucket in
              HStack {
                Text(bucket.name)
                if bucket.isPublic {
                  Image(systemName: "lock.open.fill")
                    .foregroundColor(.green)
                }
              }.tag(bucket.id)
            }
          }
        }

        TextField("File path (e.g., folder/file.jpg)", text: $filePath)
          .textInputAutocapitalization(.never)

        HStack {
          Text("Expires in (seconds)")
          TextField("3600", text: $expiresIn)
            .keyboardType(.numberPad)
            .multilineTextAlignment(.trailing)
        }
      }

      Section("Signed Download URL") {
        Text(
          "Create a temporary URL that expires after a set time, useful for sharing private files"
        )
        .font(.caption)
        .foregroundColor(.secondary)

        Button("Create Signed Download URL") {
          Task {
            await createSignedDownloadURL()
          }
        }
        .disabled(selectedBucket.isEmpty || filePath.isEmpty || isLoading)

        if let signedURL {
          VStack(alignment: .leading, spacing: 8) {
            Text("Signed URL Created!")
              .foregroundColor(.green)

            Text(signedURL.absoluteString)
              .font(.system(.caption, design: .monospaced))
              .lineLimit(3)
              .truncationMode(.middle)

            HStack {
              Button("Copy URL") {
                UIPasteboard.general.string = signedURL.absoluteString
              }

              Button("Open in Browser") {
                UIApplication.shared.open(signedURL)
              }
            }
          }
        }
      }

      Section("Signed Upload URL") {
        Text("Create a URL for uploading files without additional authentication")
          .font(.caption)
          .foregroundColor(.secondary)

        Button("Create Signed Upload URL") {
          Task {
            await createSignedUploadURL()
          }
        }
        .disabled(selectedBucket.isEmpty || filePath.isEmpty || isLoading)

        if let signedUploadURL {
          VStack(alignment: .leading, spacing: 8) {
            Text("Signed Upload URL Created!")
              .foregroundColor(.green)

            Text("URL: \(signedUploadURL.signedURL.absoluteString)")
              .font(.system(.caption, design: .monospaced))
              .lineLimit(2)
              .truncationMode(.middle)

            Text("Token: \(signedUploadURL.token)")
              .font(.system(.caption, design: .monospaced))
              .lineLimit(1)
              .truncationMode(.middle)

            Button("Copy Token") {
              UIPasteboard.general.string = signedUploadURL.token
            }
          }
        }
      }

      Section("Public URL") {
        Text("Get a permanent public URL (bucket must be public)")
          .font(.caption)
          .foregroundColor(.secondary)

        Button("Get Public URL") {
          Task {
            await getPublicURL()
          }
        }
        .disabled(selectedBucket.isEmpty || filePath.isEmpty)

        if let publicURL {
          VStack(alignment: .leading, spacing: 8) {
            Text("Public URL:")
              .foregroundColor(.green)

            Text(publicURL.absoluteString)
              .font(.system(.caption, design: .monospaced))
              .lineLimit(3)
              .truncationMode(.middle)

            HStack {
              Button("Copy URL") {
                UIPasteboard.general.string = publicURL.absoluteString
              }

              Button("Open in Browser") {
                UIApplication.shared.open(publicURL)
              }
            }
          }
        }
      }

      if isLoading {
        Section {
          ProgressView()
        }
      }

      if let error {
        Section {
          ErrorText(error)
        }
      }

      Section("Use Cases") {
        VStack(alignment: .leading, spacing: 12) {
          UseCaseRow(
            icon: "lock.shield",
            title: "Private File Sharing",
            description: "Share files from private buckets temporarily"
          )
          UseCaseRow(
            icon: "arrow.up.circle",
            title: "Client-side Uploads",
            description: "Allow uploads without backend authentication"
          )
          UseCaseRow(
            icon: "clock",
            title: "Time-limited Access",
            description: "Control how long files remain accessible"
          )
        }
      }
    }
    .navigationTitle("Signed URLs")
    .gitHubSourceLink()
    .task {
      await loadBuckets()
    }
  }

  @MainActor
  func loadBuckets() async {
    do {
      buckets = try await supabase.storage.listBuckets()
      if let firstBucket = buckets.first {
        selectedBucket = firstBucket.id
      }
    } catch {
      self.error = error
    }
  }

  @MainActor
  func createSignedDownloadURL() async {
    do {
      error = nil
      signedURL = nil
      isLoading = true
      defer { isLoading = false }

      guard let expiresInSeconds = Int(expiresIn) else {
        throw NSError(domain: "Invalid expiry time", code: -1)
      }

      signedURL = try await supabase.storage
        .from(selectedBucket)
        .createSignedURL(path: filePath, expiresIn: expiresInSeconds)
    } catch {
      self.error = error
    }
  }

  @MainActor
  func createSignedUploadURL() async {
    do {
      error = nil
      signedUploadURL = nil
      isLoading = true
      defer { isLoading = false }

      signedUploadURL = try await supabase.storage
        .from(selectedBucket)
        .createSignedUploadURL(path: filePath)
    } catch {
      self.error = error
    }
  }

  @MainActor
  func getPublicURL() async {
    do {
      error = nil
      publicURL = nil

      publicURL = try supabase.storage
        .from(selectedBucket)
        .getPublicURL(path: filePath)
    } catch {
      self.error = error
    }
  }
}

struct UseCaseRow: View {
  let icon: String
  let title: String
  let description: String

  var body: some View {
    HStack(alignment: .top, spacing: 12) {
      Image(systemName: icon)
        .font(.title2)
        .foregroundColor(.accentColor)
        .frame(width: 32)

      VStack(alignment: .leading, spacing: 2) {
        Text(title)
          .font(.subheadline)
          .fontWeight(.medium)
        Text(description)
          .font(.caption)
          .foregroundColor(.secondary)
      }
    }
  }
}
