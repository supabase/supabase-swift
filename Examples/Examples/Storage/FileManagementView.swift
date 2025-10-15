//
//  FileManagementView.swift
//  Examples
//
//  Demonstrates file move, copy, and delete operations
//

import Supabase
import SwiftUI

struct FileManagementView: View {
  @State private var selectedBucket = ""
  @State private var buckets: [Bucket] = []
  @State private var files: [FileObject] = []
  @State private var sourcePath = ""
  @State private var destinationPath = ""
  @State private var destinationBucket = ""
  @State private var error: Error?
  @State private var successMessage: String?
  @State private var isLoading = false
  @State private var selectedOperation: FileOperation = .move

  enum FileOperation: String, CaseIterable {
    case move = "Move"
    case copy = "Copy"
    case delete = "Delete"
  }

  var body: some View {
    List {
      Section {
        Text("Move, copy, and delete files in your storage buckets")
          .font(.caption)
          .foregroundColor(.secondary)
      }

      Section("Select Bucket") {
        if buckets.isEmpty {
          Text("Loading buckets...")
            .foregroundColor(.secondary)
        } else {
          Picker("Bucket", selection: $selectedBucket) {
            Text("Select a bucket").tag("")
            ForEach(buckets) { bucket in
              Text(bucket.name).tag(bucket.id)
            }
          }
        }

        Button("Load Files") {
          Task {
            await loadFiles()
          }
        }
        .disabled(selectedBucket.isEmpty || isLoading)
      }

      Section("Select Operation") {
        Picker("Operation", selection: $selectedOperation) {
          ForEach(FileOperation.allCases, id: \.self) { operation in
            Text(operation.rawValue).tag(operation)
          }
        }
        .pickerStyle(.segmented)
      }

      Section("Files in Bucket") {
        if files.isEmpty {
          Text("No files found")
            .font(.caption)
            .foregroundColor(.secondary)
        } else {
          ForEach(files) { file in
            HStack {
              VStack(alignment: .leading, spacing: 2) {
                Text(file.name)
                  .font(.subheadline)

                if let createdAt = file.createdAt {
                  Text(createdAt, style: .relative)
                    .font(.caption)
                    .foregroundColor(.secondary)
                }
              }

              Spacer()

              Button {
                sourcePath = file.name
              } label: {
                Image(systemName: sourcePath == file.name ? "checkmark.circle.fill" : "circle")
                  .foregroundColor(sourcePath == file.name ? .accentColor : .gray)
              }
            }
          }
        }
      }

      if selectedOperation != .delete {
        Section("Destination") {
          TextField("Destination path", text: $destinationPath)
            .textInputAutocapitalization(.never)

          if selectedOperation == .move || selectedOperation == .copy {
            Picker("Destination Bucket (optional)", selection: $destinationBucket) {
              Text("Same bucket").tag("")
              ForEach(buckets.filter { $0.id != selectedBucket }) { bucket in
                Text(bucket.name).tag(bucket.id)
              }
            }
          }
        }
      }

      Section {
        Button(selectedOperation.rawValue + " File") {
          Task {
            await performOperation()
          }
        }
        .disabled(
          sourcePath.isEmpty || isLoading
            || (selectedOperation != .delete && destinationPath.isEmpty)
        )
      }

      if isLoading {
        Section {
          ProgressView()
        }
      }

      if let successMessage {
        Section {
          Text(successMessage)
            .foregroundColor(.green)
        }
      }

      if let error {
        Section {
          ErrorText(error)
        }
      }

      Section("Code Examples") {
        CodeExample(
          code: """
            // Move a file
            try await supabase.storage
              .from("my-bucket")
              .move(
                from: "folder/old-name.jpg",
                to: "folder/new-name.jpg"
              )
            """
        )

        CodeExample(
          code: """
            // Move to different bucket
            try await supabase.storage
              .from("source-bucket")
              .move(
                from: "file.jpg",
                to: "file.jpg",
                options: DestinationOptions(
                  destinationBucket: "target-bucket"
                )
              )
            """
        )

        CodeExample(
          code: """
            // Copy a file
            let newPath = try await supabase.storage
              .from("my-bucket")
              .copy(
                from: "folder/original.jpg",
                to: "folder/copy.jpg"
              )

            print("Copied to:", newPath)
            """
        )

        CodeExample(
          code: """
            // Delete single file
            try await supabase.storage
              .from("my-bucket")
              .remove(paths: ["folder/file.jpg"])
            """
        )

        CodeExample(
          code: """
            // Delete multiple files
            let removed = try await supabase.storage
              .from("my-bucket")
              .remove(paths: [
                "folder/file1.jpg",
                "folder/file2.jpg",
                "folder/file3.jpg"
              ])

            print("Removed \\(removed.count) files")
            """
        )
      }

      Section("Tips") {
        VStack(alignment: .leading, spacing: 8) {
          TipRow(
            icon: "arrow.right.arrow.left",
            text: "Move operations rename or relocate files atomically"
          )
          TipRow(
            icon: "doc.on.doc",
            text: "Copy creates a duplicate while preserving the original"
          )
          TipRow(
            icon: "trash",
            text: "Delete operations are permanent and cannot be undone"
          )
          TipRow(
            icon: "folder.badge.questionmark",
            text: "You can move/copy files between different buckets"
          )
        }
      }
    }
    .navigationTitle("File Management")
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
  func loadFiles() async {
    do {
      error = nil
      isLoading = true
      defer { isLoading = false }

      files = try await supabase.storage
        .from(selectedBucket)
        .list()
    } catch {
      self.error = error
    }
  }

  @MainActor
  func performOperation() async {
    do {
      error = nil
      successMessage = nil
      isLoading = true
      defer { isLoading = false }

      switch selectedOperation {
      case .move:
        let options =
          destinationBucket.isEmpty
          ? nil
          : DestinationOptions(
            destinationBucket: destinationBucket
          )
        try await supabase.storage
          .from(selectedBucket)
          .move(from: sourcePath, to: destinationPath, options: options)
        successMessage = "File moved successfully to \(destinationPath)"

      case .copy:
        let options =
          destinationBucket.isEmpty
          ? nil
          : DestinationOptions(
            destinationBucket: destinationBucket
          )
        let newPath = try await supabase.storage
          .from(selectedBucket)
          .copy(from: sourcePath, to: destinationPath, options: options)
        successMessage = "File copied successfully to \(newPath)"

      case .delete:
        let removed = try await supabase.storage
          .from(selectedBucket)
          .remove(paths: [sourcePath])
        successMessage = "Deleted \(removed.count) file(s)"
      }

      // Reset and reload
      sourcePath = ""
      destinationPath = ""
      destinationBucket = ""
      await loadFiles()
    } catch {
      self.error = error
    }
  }
}

struct TipRow: View {
  let icon: String
  let text: String

  var body: some View {
    HStack(alignment: .top, spacing: 12) {
      Image(systemName: icon)
        .foregroundColor(.accentColor)
        .frame(width: 24)
      Text(text)
        .font(.caption)
    }
  }
}
