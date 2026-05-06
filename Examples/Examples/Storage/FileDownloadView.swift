//
//  FileDownloadView.swift
//  Examples
//
//  Demonstrates both download engines:
//    - To Memory (downloadData): loads file bytes in-process, previews images and text
//    - To Disk (download): saves to a temporary file; background-session capable, survives app suspension
//

import Supabase
import SwiftUI

struct FileDownloadView: View {

  // MARK: - Download mode

  enum DownloadMode: String, CaseIterable, Identifiable {
    case toMemory = "To Memory"
    case toDisk = "To Disk"

    var id: Self { self }

    var description: String {
      switch self {
      case .toMemory:
        return "Loads the file into memory. Supports image and text preview."
      case .toDisk:
        return "Saves to a temporary file. Background-session capable \u{2014} transfer continues while the app is suspended."
      }
    }
  }

  // MARK: - State

  @State private var selectedBucket = ""
  @State private var buckets: [Bucket] = []
  @State private var files: [FileObject] = []
  @State private var downloadMode: DownloadMode = .toMemory
  @State private var selectedPath = ""

  // Transfer state
  @State private var isDownloading = false
  @State private var downloadProgress: Double = 0
  @State private var error: Error?

  // Results
  @State private var downloadedData: Data?
  @State private var downloadedImage: UIImage?
  @State private var downloadedText: String?
  @State private var downloadedFileURL: URL?

  // MARK: - Body

  var body: some View {
    List {
      descriptionSection
      modeSection
      bucketSection
      filesSection

      if isDownloading {
        transferSection
      }

      if let downloadedImage {
        imagePreviewSection(downloadedImage)
      } else if let downloadedText {
        textPreviewSection(downloadedText)
      } else if let downloadedData {
        dataSection(downloadedData)
      } else if let downloadedFileURL {
        diskSection(downloadedFileURL)
      }

      if let error {
        Section { ErrorText(error) }
      }
    }
    .navigationTitle("Download Files")
    .gitHubSourceLink()
    .task { await loadBuckets() }
    .onChange(of: selectedBucket) { _, _ in clearResults() }
    .onChange(of: downloadMode) { _, _ in clearResults() }
  }

  // MARK: - Sections

  private var descriptionSection: some View {
    Section {
      Text("Download files to memory or to disk. Disk downloads are background-session capable.")
        .font(.caption)
        .foregroundColor(.secondary)
    }
  }

  private var modeSection: some View {
    Section("Download Mode") {
      Picker("Mode", selection: $downloadMode) {
        ForEach(DownloadMode.allCases) { mode in
          Text(mode.rawValue).tag(mode)
        }
      }
      .pickerStyle(.segmented)

      Text(downloadMode.description)
        .font(.caption)
        .foregroundColor(.secondary)
    }
  }

  private var bucketSection: some View {
    Section("Select Bucket") {
      if buckets.isEmpty {
        Text("Loading buckets…")
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
        Task { await loadFiles() }
      }
      .disabled(selectedBucket.isEmpty || isDownloading)
    }
  }

  private var filesSection: some View {
    Section("Files in Bucket") {
      if files.isEmpty {
        Text("No files found — select a bucket and tap \"Load Files\"")
          .font(.caption)
          .foregroundColor(.secondary)
      } else {
        ForEach(files) { file in
          HStack {
            Image(systemName: iconForFile(file))
              .foregroundColor(.accentColor)

            VStack(alignment: .leading, spacing: 2) {
              Text(file.name).font(.subheadline)
              if let size = file.metadata?["size"]?.intValue {
                Text(ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file))
                  .font(.caption)
                  .foregroundColor(.secondary)
              }
            }

            Spacer()

            Button {
              selectedPath = file.name
              Task { await downloadFile(path: file.name) }
            } label: {
              Image(systemName: "arrow.down.circle.fill").font(.title3)
            }
            .disabled(isDownloading)
          }
        }
      }
    }
  }

  private var transferSection: some View {
    Section("Transfer") {
      ProgressView(value: downloadProgress) {
        HStack {
          Text("Downloading…")
          Spacer()
          Text("\(Int(downloadProgress * 100))%")
        }
        .font(.caption)
        .foregroundColor(.secondary)
      }
    }
  }

  private func imagePreviewSection(_ image: UIImage) -> some View {
    Section("Image Preview") {
      Image(uiImage: image)
        .resizable()
        .scaledToFit()
        .frame(maxHeight: 300)
        .cornerRadius(8)

      HStack {
        Text("Dimensions")
        Spacer()
        Text("\(Int(image.size.width)) × \(Int(image.size.height)) px")
          .foregroundColor(.secondary)
      }
      .font(.caption)

      downloadModeLabel

      Button("Share Image") { shareImage(image) }
    }
  }

  private func textPreviewSection(_ text: String) -> some View {
    Section("Text Preview") {
      Text(text)
        .font(.system(.body, design: .monospaced))
        .padding(8)
        .background(Color(.systemGray6))
        .cornerRadius(8)

      downloadModeLabel
    }
  }

  private func dataSection(_ data: Data) -> some View {
    Section("Downloaded (in memory)") {
      Label("File loaded into memory", systemImage: "checkmark.circle.fill")
        .foregroundColor(.green)
      HStack {
        Text("Size")
        Spacer()
        Text(ByteCountFormatter.string(fromByteCount: Int64(data.count), countStyle: .file))
          .foregroundColor(.secondary)
      }
      .font(.caption)
      Text("Path: \(selectedPath)").font(.caption).foregroundColor(.secondary)
      downloadModeLabel
    }
  }

  private func diskSection(_ url: URL) -> some View {
    Section("Downloaded (on disk)") {
      Label("File saved to disk", systemImage: "checkmark.circle.fill")
        .foregroundColor(.green)
      Text("Temporary URL:")
        .font(.caption)
        .foregroundColor(.secondary)
      Text(url.path)
        .font(.system(.caption, design: .monospaced))
        .foregroundColor(.secondary)
        .lineLimit(3)
      downloadModeLabel
    }
  }

  private var downloadModeLabel: some View {
    Text("Mode: \(downloadMode.rawValue)")
      .font(.caption)
      .foregroundColor(.secondary)
  }

  // MARK: - Actions

  @MainActor
  func loadBuckets() async {
    do {
      buckets = try await supabase.storage.listBuckets()
      if let first = buckets.first { selectedBucket = first.id }
    } catch {
      self.error = error
    }
  }

  @MainActor
  func loadFiles() async {
    do {
      error = nil
      isDownloading = true
      defer { isDownloading = false }
      files = try await supabase.storage.from(selectedBucket).list()
    } catch {
      self.error = error
    }
  }

  @MainActor
  func downloadFile(path: String) async {
    clearResults()
    error = nil
    downloadProgress = 0
    isDownloading = true

    let bucket = supabase.storage.from(selectedBucket)

    switch downloadMode {

    case .toMemory:
      // downloadData returns StorageTransferTask<Data> — drives progress events, loads into memory
      let task = bucket.downloadData(path: path)
      for await event in task.events {
        switch event {
        case .progress(let p):
          downloadProgress = p.fractionCompleted
        case .completed(let data):
          downloadProgress = 1.0
          downloadedData = data
          if let image = UIImage(data: data) {
            downloadedImage = image
            downloadedData = nil
          } else if let text = String(data: data, encoding: .utf8) {
            downloadedText = text
            downloadedData = nil
          }
        case .failed(let storageError):
          self.error = storageError
        }
      }

    case .toDisk:
      // download returns StorageDownloadTask (StorageTransferTask<URL>) — background-session capable
      let task = bucket.download(path: path)
      for await event in task.events {
        switch event {
        case .progress(let p):
          downloadProgress = p.fractionCompleted
        case .completed(let url):
          downloadProgress = 1.0
          downloadedFileURL = url
          // Try to show a preview even for disk downloads
          if let data = try? Data(contentsOf: url) {
            if let image = UIImage(data: data) {
              downloadedImage = image
              downloadedFileURL = nil
            } else if let text = String(data: data, encoding: .utf8) {
              downloadedText = text
              downloadedFileURL = nil
            }
          }
        case .failed(let storageError):
          self.error = storageError
        }
      }
    }

    isDownloading = false
  }

  func clearResults() {
    downloadedData = nil
    downloadedImage = nil
    downloadedText = nil
    downloadedFileURL = nil
    downloadProgress = 0
  }

  func shareImage(_ image: UIImage) {
    let vc = UIActivityViewController(activityItems: [image], applicationActivities: nil)
    if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
      let root = windowScene.windows.first?.rootViewController
    {
      root.present(vc, animated: true)
    }
  }

  func iconForFile(_ file: FileObject) -> String {
    let name = file.name.lowercased()
    if name.hasSuffix(".jpg") || name.hasSuffix(".jpeg") || name.hasSuffix(".png")
      || name.hasSuffix(".gif") || name.hasSuffix(".webp")
    {
      return "photo"
    } else if name.hasSuffix(".pdf") {
      return "doc.fill"
    } else if name.hasSuffix(".txt") || name.hasSuffix(".md") {
      return "doc.text"
    } else if name.hasSuffix(".mp4") || name.hasSuffix(".mov") {
      return "video"
    }
    return "doc"
  }
}
