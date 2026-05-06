//
//  FileDownloadView.swift
//  Examples
//
//  Demonstrates both download engines:
//    - To Memory (downloadData): loads file bytes in-process
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
        return "Loads file bytes into memory via downloadData()."
      case .toDisk:
        return
          "Saves to a temporary file via download(). Background-session capable — transfer continues while the app is suspended."
      }
    }
  }

  // MARK: - Result

  enum DownloadResult {
    case inMemory(Data, path: String)
    case onDisk(URL)
  }

  // MARK: - State

  @State private var selectedBucket = ""
  @State private var buckets: [Bucket] = []
  @State private var files: [FileObject] = []
  @State private var downloadMode: DownloadMode = .toMemory

  // Transfer state
  @State private var isDownloading = false
  @State private var downloadProgress: Double = 0
  @State private var result: DownloadResult?
  @State private var error: Error?

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

      if let result {
        resultSection(result)
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

  @ViewBuilder
  private func resultSection(_ result: DownloadResult) -> some View {
    switch result {
    case .inMemory(let data, let path):
      Section("Downloaded (in memory)") {
        Label("File loaded into memory", systemImage: "checkmark.circle.fill")
          .foregroundColor(.green)
        row("Size", ByteCountFormatter.string(fromByteCount: Int64(data.count), countStyle: .file))
        row("Path", path)
        row("Mode", downloadMode.rawValue)
      }

    case .onDisk(let url):
      Section("Downloaded (on disk)") {
        Label("File saved to disk", systemImage: "checkmark.circle.fill")
          .foregroundColor(.green)
        if let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize {
          row("Size", ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file))
        }
        row("Mode", downloadMode.rawValue)
        Text(url.path)
          .font(.system(.caption, design: .monospaced))
          .foregroundColor(.secondary)
          .lineLimit(4)
      }
    }
  }

  private func row(_ label: String, _ value: String) -> some View {
    HStack {
      Text(label)
      Spacer()
      Text(value).foregroundColor(.secondary)
    }
    .font(.caption)
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
      let task = bucket.downloadData(path: path)
      for await event in task.events {
        switch event {
        case .progress(let p):
          downloadProgress = p.fractionCompleted
        case .completed(let data):
          downloadProgress = 1.0
          result = .inMemory(data, path: path)
        case .failed(let storageError):
          self.error = storageError
        }
      }

    case .toDisk:
      let task = bucket.download(path: path)
      for await event in task.events {
        switch event {
        case .progress(let p):
          downloadProgress = p.fractionCompleted
        case .completed(let url):
          downloadProgress = 1.0
          result = .onDisk(url)
        case .failed(let storageError):
          self.error = storageError
        }
      }
    }

    isDownloading = false
  }

  func clearResults() {
    result = nil
    downloadProgress = 0
    error = nil
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
