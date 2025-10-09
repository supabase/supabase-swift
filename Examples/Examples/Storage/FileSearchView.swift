//
//  FileSearchView.swift
//  Examples
//
//  Demonstrates file search, listing with options, and metadata
//

import Supabase
import SwiftUI

struct FileSearchView: View {
  @State private var selectedBucket = ""
  @State private var buckets: [Bucket] = []
  @State private var files: [FileObject] = []
  @State private var searchText = ""
  @State private var folderPath = ""
  @State private var sortColumn: SortColumn = .name
  @State private var sortOrder: SortOrder = .ascending
  @State private var limit = "100"
  @State private var selectedFile: FileObjectV2?
  @State private var error: Error?
  @State private var isLoading = false

  enum SortColumn: String, CaseIterable {
    case name = "name"
    case createdAt = "created_at"
    case updatedAt = "updated_at"

    var displayName: String {
      switch self {
      case .name: return "Name"
      case .createdAt: return "Created"
      case .updatedAt: return "Updated"
      }
    }
  }

  enum SortOrder: String, CaseIterable {
    case ascending = "asc"
    case descending = "desc"

    var displayName: String {
      switch self {
      case .ascending: return "Ascending"
      case .descending: return "Descending"
      }
    }
  }

  var body: some View {
    List {
      Section {
        Text("Search and filter files with advanced options")
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
      }

      Section("Search Options") {
        TextField("Search files", text: $searchText)
          .textInputAutocapitalization(.never)

        TextField("Folder path (optional)", text: $folderPath)
          .textInputAutocapitalization(.never)

        Picker("Sort by", selection: $sortColumn) {
          ForEach(SortColumn.allCases, id: \.self) { column in
            Text(column.displayName).tag(column)
          }
        }

        Picker("Order", selection: $sortOrder) {
          ForEach(SortOrder.allCases, id: \.self) { order in
            Text(order.displayName).tag(order)
          }
        }

        HStack {
          Text("Limit")
          TextField("100", text: $limit)
            .keyboardType(.numberPad)
            .multilineTextAlignment(.trailing)
        }

        Button("Search Files") {
          Task {
            await searchFiles()
          }
        }
        .disabled(selectedBucket.isEmpty || isLoading)
      }

      Section("Results (\(files.count))") {
        if files.isEmpty {
          Text("No files found")
            .font(.caption)
            .foregroundColor(.secondary)
        } else {
          ForEach(files) { file in
            Button {
              Task {
                await loadFileInfo(file.name)
              }
            } label: {
              HStack {
                Image(systemName: iconForFile(file))
                  .foregroundColor(.accentColor)

                VStack(alignment: .leading, spacing: 2) {
                  Text(file.name)
                    .font(.subheadline)
                    .foregroundColor(.primary)

                  if let createdAt = file.createdAt {
                    Text(createdAt, style: .relative)
                      .font(.caption)
                      .foregroundColor(.secondary)
                  }
                }

                Spacer()

                Image(systemName: "info.circle")
                  .foregroundColor(.secondary)
              }
            }
          }
        }
      }

      if let selectedFile {
        Section("File Details") {
          DetailRow(label: "Name", value: selectedFile.name)
          DetailRow(label: "ID", value: selectedFile.id)
          DetailRow(label: "Version", value: selectedFile.version)

          if let contentType = selectedFile.contentType {
            DetailRow(label: "Content Type", value: contentType)
          }

          if let size = selectedFile.size {
            DetailRow(
              label: "Size",
              value: ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file)
            )
          }

          if let cacheControl = selectedFile.cacheControl {
            DetailRow(label: "Cache Control", value: cacheControl)
          }

          if let createdAt = selectedFile.createdAt {
            DetailRow(label: "Created", value: createdAt.formatted())
          }

          if let updatedAt = selectedFile.updatedAt {
            DetailRow(label: "Updated", value: updatedAt.formatted())
          }

          if let lastModified = selectedFile.lastModified {
            DetailRow(label: "Last Modified", value: lastModified.formatted())
          }

          if let etag = selectedFile.etag {
            DetailRow(label: "ETag", value: etag)
          }

          if let metadata = selectedFile.metadata, !metadata.isEmpty {
            Text("Metadata:")
              .font(.caption)
              .foregroundColor(.secondary)

            ForEach(Array(metadata.keys.sorted()), id: \.self) { key in
              if let value = metadata[key] {
                DetailRow(label: key, value: String(describing: value))
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

      Section("Code Examples") {
        CodeExample(
          code: """
            // List files with options
            let files = try await supabase.storage
              .from("my-bucket")
              .list(
                path: "folder/subfolder",
                options: SearchOptions(
                  limit: 100,
                  offset: 0,
                  sortBy: SortBy(
                    column: "\(sortColumn.rawValue)",
                    order: "\(sortOrder.rawValue)"
                  ),
                  search: "\(searchText.isEmpty ? "photo" : searchText)"
                )
              )
            """
        )

        CodeExample(
          code: """
            // Get detailed file information
            let fileInfo = try await supabase.storage
              .from("my-bucket")
              .info(path: "folder/file.jpg")

            print("Size:", fileInfo.size)
            print("Type:", fileInfo.contentType)
            print("ETag:", fileInfo.etag)
            """
        )

        CodeExample(
          code: """
            // Check if file exists
            let exists = try await supabase.storage
              .from("my-bucket")
              .exists(path: "folder/file.jpg")

            if exists {
              // File is available
            }
            """
        )
      }
    }
    .navigationTitle("Search & Metadata")
    .task {
      await loadBuckets()
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
  func searchFiles() async {
    do {
      error = nil
      selectedFile = nil
      isLoading = true
      defer { isLoading = false }

      let options = SearchOptions(
        limit: Int(limit),
        offset: 0,
        sortBy: SortBy(
          column: sortColumn.rawValue,
          order: sortOrder.rawValue
        ),
        search: searchText.isEmpty ? nil : searchText
      )

      files = try await supabase.storage
        .from(selectedBucket)
        .list(
          path: folderPath.isEmpty ? nil : folderPath,
          options: options
        )
    } catch {
      self.error = error
    }
  }

  @MainActor
  func loadFileInfo(_ path: String) async {
    do {
      error = nil
      isLoading = true
      defer { isLoading = false }

      selectedFile = try await supabase.storage
        .from(selectedBucket)
        .info(path: path)
    } catch {
      self.error = error
    }
  }
}

struct DetailRow: View {
  let label: String
  let value: String

  var body: some View {
    HStack(alignment: .top) {
      Text(label)
        .font(.caption)
        .foregroundColor(.secondary)
        .frame(width: 100, alignment: .leading)

      Text(value)
        .font(.caption)
        .lineLimit(3)
    }
  }
}
