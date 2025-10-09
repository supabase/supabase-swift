//
//  FileDownloadView.swift
//  Examples
//
//  Demonstrates file download and preview functionality
//

import Supabase
import SwiftUI

struct FileDownloadView: View {
  @State private var selectedBucket = ""
  @State private var buckets: [Bucket] = []
  @State private var files: [FileObject] = []
  @State private var downloadedData: Data?
  @State private var downloadedImage: UIImage?
  @State private var downloadedText: String?
  @State private var error: Error?
  @State private var isLoading = false
  @State private var selectedPath = ""

  var body: some View {
    List {
      Section {
        Text("Download and preview files from storage")
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

      Section("Files in Bucket") {
        if files.isEmpty {
          Text("No files found or select a bucket")
            .font(.caption)
            .foregroundColor(.secondary)
        } else {
          ForEach(files) { file in
            HStack {
              Image(systemName: iconForFile(file))
                .foregroundColor(.accentColor)

              VStack(alignment: .leading, spacing: 2) {
                Text(file.name)
                  .font(.subheadline)

                if let metadata = file.metadata, let size = metadata["size"]?.intValue {
                  Text(ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file))
                    .font(.caption)
                    .foregroundColor(.secondary)
                }
              }

              Spacer()

              Button {
                selectedPath = file.name
                Task {
                  await downloadFile(path: file.name)
                }
              } label: {
                Image(systemName: "arrow.down.circle.fill")
                  .font(.title3)
              }
              .disabled(isLoading)
            }
          }
        }
      }

      if isLoading {
        Section {
          ProgressView("Downloading...")
        }
      }

      // Preview Section
      if let downloadedImage {
        Section("Image Preview") {
          Image(uiImage: downloadedImage)
            .resizable()
            .scaledToFit()
            .frame(maxHeight: 300)
            .cornerRadius(8)

          Button("Share Image") {
            shareImage(downloadedImage)
          }
        }
      }

      if let downloadedText {
        Section("Text Preview") {
          Text(downloadedText)
            .font(.system(.body, design: .monospaced))
            .padding()
            .background(Color(.systemGray6))
            .cornerRadius(8)
        }
      }

      if let downloadedData, downloadedImage == nil, downloadedText == nil {
        Section("Downloaded") {
          VStack(alignment: .leading, spacing: 4) {
            Text("File downloaded successfully")
              .foregroundColor(.green)
            Text(
              "Size: \(ByteCountFormatter.string(fromByteCount: Int64(downloadedData.count), countStyle: .file))"
            )
            .font(.caption)
            .foregroundColor(.secondary)
            Text("Path: \(selectedPath)")
              .font(.caption)
              .foregroundColor(.secondary)
          }
        }
      }

      if let error {
        Section {
          ErrorText(error)
        }
      }

    }
    .navigationTitle("Download Files")
    .gitHubSourceLink()
    .task {
      await loadBuckets()
    }
    .onChange(of: selectedBucket) { _, _ in
      files = []
      downloadedData = nil
      downloadedImage = nil
      downloadedText = nil
    }
  }

  func iconForFile(_ file: FileObject) -> String {
    let name = file.name.lowercased()
    if name.hasSuffix(".jpg") || name.hasSuffix(".jpeg") || name.hasSuffix(".png")
      || name
        .hasSuffix(".gif")
    {
      return "photo"
    } else if name.hasSuffix(".pdf") {
      return "doc.fill"
    } else if name.hasSuffix(".txt") {
      return "doc.text"
    } else if name.hasSuffix(".mp4") || name.hasSuffix(".mov") {
      return "video"
    }
    return "doc"
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
  func downloadFile(path: String) async {
    do {
      error = nil
      downloadedData = nil
      downloadedImage = nil
      downloadedText = nil
      isLoading = true
      defer { isLoading = false }

      let data = try await supabase.storage
        .from(selectedBucket)
        .download(path: path)

      downloadedData = data

      // Try to convert to image
      if let image = UIImage(data: data) {
        downloadedImage = image
      }
      // Try to convert to text
      else if let text = String(data: data, encoding: .utf8) {
        downloadedText = text
      }
    } catch {
      self.error = error
    }
  }

  func shareImage(_ image: UIImage) {
    let activityController = UIActivityViewController(
      activityItems: [image],
      applicationActivities: nil
    )

    if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
      let window = windowScene.windows.first,
      let rootViewController = window.rootViewController
    {
      rootViewController.present(activityController, animated: true)
    }
  }
}
