//
//  BucketOperationsView.swift
//  Examples
//
//  Demonstrates bucket create, update, delete, and empty operations
//

import Supabase
import SwiftUI

struct BucketOperationsView: View {
  @State private var bucketName = ""
  @State private var isPublic = false
  @State private var fileSizeLimit = ""
  @State private var selectedBucket: Bucket?
  @State private var buckets: [Bucket] = []
  @State private var error: Error?
  @State private var successMessage: String?
  @State private var isLoading = false

  var body: some View {
    List {
      Section {
        Text("Create and manage storage buckets")
          .font(.caption)
          .foregroundColor(.secondary)
      }

      // Create Bucket
      Section("Create New Bucket") {
        TextField("Bucket name", text: $bucketName)
          .textInputAutocapitalization(.never)
          .autocorrectionDisabled()

        Toggle("Public Access", isOn: $isPublic)

        TextField("File size limit (optional, e.g., 52428800 for 50MB)", text: $fileSizeLimit)
          .keyboardType(.numberPad)

        Button("Create Bucket") {
          Task {
            await createBucket()
          }
        }
        .disabled(bucketName.isEmpty || isLoading)
      }

      // Existing Buckets
      Section("Existing Buckets") {
        Button("Refresh List") {
          Task {
            await loadBuckets()
          }
        }

        ForEach(buckets) { bucket in
          VStack(alignment: .leading, spacing: 4) {
            HStack {
              Image(systemName: bucket.isPublic ? "lock.open.fill" : "lock.fill")
                .foregroundColor(bucket.isPublic ? .green : .orange)
              Text(bucket.name)
                .font(.headline)
            }

            if let limit = bucket.fileSizeLimit {
              Text(
                "Max size: \(ByteCountFormatter.string(fromByteCount: limit, countStyle: .file))"
              )
              .font(.caption)
              .foregroundColor(.secondary)
            }

            HStack(spacing: 12) {
              Button("Make \(bucket.isPublic ? "Private" : "Public")") {
                Task {
                  await toggleBucketVisibility(bucket)
                }
              }
              .font(.caption)
              .disabled(isLoading)

              Button("Empty") {
                Task {
                  await emptyBucket(bucket)
                }
              }
              .font(.caption)
              .foregroundColor(.orange)
              .disabled(isLoading)

              Button("Delete") {
                Task {
                  await deleteBucket(bucket)
                }
              }
              .font(.caption)
              .foregroundColor(.red)
              .disabled(isLoading)
            }
          }
          .padding(.vertical, 4)
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

      if let successMessage {
        Section {
          Text(successMessage)
            .foregroundColor(.green)
        }
      }

      Section("Code Examples") {
        CodeExample(
          code: """
            // Create a bucket
            try await supabase.storage.createBucket(
              "my-bucket",
              options: BucketOptions(
                public: true,
                fileSizeLimit: "52428800"  // 50MB
              )
            )
            """
        )

        CodeExample(
          code: """
            // Update bucket settings
            try await supabase.storage.updateBucket(
              "my-bucket",
              options: BucketOptions(
                public: false,
                fileSizeLimit: "10485760"  // 10MB
              )
            )
            """
        )

        CodeExample(
          code: """
            // Empty a bucket (remove all files)
            try await supabase.storage.emptyBucket("my-bucket")

            // Delete a bucket
            try await supabase.storage.deleteBucket("my-bucket")
            """
        )
      }
    }
    .navigationTitle("Bucket Operations")
    .task {
      await loadBuckets()
    }
  }

  @MainActor
  func createBucket() async {
    do {
      error = nil
      successMessage = nil
      isLoading = true
      defer { isLoading = false }

      var options = BucketOptions(public: isPublic)
      if !fileSizeLimit.isEmpty, let limit = Int64(fileSizeLimit) {
        options.fileSizeLimit = String(limit)
      }

      try await supabase.storage.createBucket(bucketName, options: options)

      successMessage = "Bucket '\(bucketName)' created successfully!"
      bucketName = ""
      fileSizeLimit = ""
      isPublic = false

      await loadBuckets()
    } catch {
      self.error = error
    }
  }

  @MainActor
  func loadBuckets() async {
    do {
      error = nil
      isLoading = true
      defer { isLoading = false }

      buckets = try await supabase.storage.listBuckets()
    } catch {
      self.error = error
    }
  }

  @MainActor
  func toggleBucketVisibility(_ bucket: Bucket) async {
    do {
      error = nil
      successMessage = nil
      isLoading = true
      defer { isLoading = false }

      let newPublic = !bucket.isPublic
      let options = BucketOptions(
        public: newPublic,
        fileSizeLimit: bucket.fileSizeLimit.map(String.init)
      )

      try await supabase.storage.updateBucket(bucket.id, options: options)

      successMessage = "Bucket '\(bucket.name)' is now \(newPublic ? "public" : "private")"
      await loadBuckets()
    } catch {
      self.error = error
    }
  }

  @MainActor
  func emptyBucket(_ bucket: Bucket) async {
    do {
      error = nil
      successMessage = nil
      isLoading = true
      defer { isLoading = false }

      try await supabase.storage.emptyBucket(bucket.id)

      successMessage = "Bucket '\(bucket.name)' emptied successfully!"
    } catch {
      self.error = error
    }
  }

  @MainActor
  func deleteBucket(_ bucket: Bucket) async {
    do {
      error = nil
      successMessage = nil
      isLoading = true
      defer { isLoading = false }

      try await supabase.storage.deleteBucket(bucket.id)

      successMessage = "Bucket '\(bucket.name)' deleted successfully!"
      await loadBuckets()
    } catch {
      self.error = error
    }
  }
}
