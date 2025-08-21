//
//  StorageUploadView.swift
//  Examples
//
//  Created by Claude Code on 21/08/25.
//

import Supabase
import SwiftUI
import UniformTypeIdentifiers

enum UploadMethod: String, CaseIterable {
  case data = "Data"
  case file = "File"

  var title: String { rawValue }
}

enum TestFileSize: String, CaseIterable {
  case small = "Small (1KB)"
  case medium = "Medium (100KB)"
  case large = "Large (10MB)"
  case extraLarge = "Extra Large (50MB)"
  case huge = "Huge (1GB)"

  var bytes: Int {
    switch self {
    case .small: return 1_024
    case .medium: return 100_000
    case .large: return 10_000_000
    case .extraLarge: return 50_000_000
    case .huge: return 1_000_000_000
    }
  }

  var title: String { rawValue }
}

struct StorageUploadView: View {
  let bucket: Bucket

  @State private var uploadMethod: UploadMethod = .data
  @State private var testFileSize: TestFileSize = .small
  @State private var fileName: String = ""
  @State private var uploadResult = ActionState<String, Error>.idle
  @State private var lastUploadedFile: (name: String, result: String)?
  @State private var showingFilePicker = false
  @State private var selectedFileURL: URL?

  private var generatedFileName: String {
    if !fileName.isEmpty {
      return fileName
    }

    switch uploadMethod {
    case .data:
      return
        "test-\(testFileSize.rawValue.lowercased().replacingOccurrences(of: " ", with: "-"))-\(UUID().uuidString.prefix(8)).txt"
    case .file:
      return selectedFileURL?.lastPathComponent ?? "selected-file-\(UUID().uuidString.prefix(8))"
    }
  }

  var body: some View {
    Form {
      Section("Upload Configuration") {
        Picker("Upload Method", selection: $uploadMethod) {
          ForEach(UploadMethod.allCases, id: \.self) { method in
            Text(method.title).tag(method)
          }
        }
        .pickerStyle(.segmented)

        if uploadMethod == .data {
          Picker("File Size", selection: $testFileSize) {
            ForEach(TestFileSize.allCases, id: \.self) { size in
              Text(size.title).tag(size)
            }
          }
        } else {
          VStack(alignment: .leading, spacing: 8) {
            Button("Select File") {
              showingFilePicker = true
            }

            if let selectedFileURL {
              Text("Selected: \(selectedFileURL.lastPathComponent)")
                .font(.caption)
                .foregroundColor(.secondary)
            } else {
              Text("No file selected")
                .font(.caption)
                .foregroundColor(.secondary)
            }
          }
        }

        TextField("File Name (optional)", text: $fileName)
          .textInputAutocapitalization(.never)

        Text("Generated file name: \(generatedFileName)")
          .font(.caption)
          .foregroundColor(.secondary)
      }

      Section("Actions") {
        Button("Upload File") {
          Task {
            await uploadFile()
          }
        }
        .disabled(uploadResult.isInFlight || (uploadMethod == .file && selectedFileURL == nil))

        if uploadResult.isInFlight {
          HStack {
            ProgressView()
              .scaleEffect(0.8)
            Text("Uploading...")
              .font(.caption)
          }
        }
      }

      if let lastUploadedFile {
        Section("Last Upload Result") {
          VStack(alignment: .leading, spacing: 8) {
            Text("File: \(lastUploadedFile.name)")
              .font(.headline)
            Text(lastUploadedFile.result)
              .font(.system(.caption, design: .monospaced))
              .textSelection(.enabled)
          }
        }
      }

      if case let .result(.failure(error)) = uploadResult {
        Section("Error") {
          ErrorText(error)
        }
      }

      Section("Upload Methods Info") {
        VStack(alignment: .leading, spacing: 8) {
          Label("Data Upload", systemImage: "doc.badge.plus")
          Text("Generates test data of specified size and uploads directly")
            .font(.caption)
            .foregroundColor(.secondary)

          Divider()

          Label("File Upload", systemImage: "folder.badge.plus")
          Text("Select a local file from your device and upload to storage")
            .font(.caption)
            .foregroundColor(.secondary)
        }
      }
    }
    .navigationTitle("Upload Files")
    .navigationBarTitleDisplayMode(.inline)
    .fileImporter(
      isPresented: $showingFilePicker,
      allowedContentTypes: [.data],
      allowsMultipleSelection: false
    ) { result in
      switch result {
      case .success(let urls):
        selectedFileURL = urls.first
      case .failure:
        selectedFileURL = nil
      }
    }
  }

  @MainActor
  private func uploadFile() async {
    uploadResult = .inFlight

    do {
      let result: String
      let finalFileName = generatedFileName

      switch uploadMethod {
      case .data:
        let testData = generateTestData(size: testFileSize.bytes)
        let uploadResponse = try await supabase.storage
          .from(bucket.id)
          .upload(
            finalFileName,
            data: testData
          )
        result = "Data upload successful:\n\(stringfy(uploadResponse))"

      case .file:
        guard let fileURL = selectedFileURL else {
          throw URLError(.fileDoesNotExist)
        }

        let fileSize = try FileManager.default.attributesOfItem(atPath: fileURL.path)[
          FileAttributeKey.size
        ]

        let uploadResponse = try await supabase.storage
          .from(bucket.id)
          .upload(
            finalFileName,
            fileURL: fileURL
          )
        result =
          "File upload successful:\nFile: \(fileURL.lastPathComponent)\nSize: \(String(describing: fileSize)) bytes\n\(stringfy(uploadResponse))"
      }

      uploadResult = .result(.success(result))
      lastUploadedFile = (finalFileName, result)

    } catch {
      uploadResult = .result(.failure(error))
    }
  }

  private func generateTestData(size: Int) -> Data {
    let pattern = "This is test data for storage upload testing. "
    let patternData = pattern.data(using: .utf8) ?? Data()
    let patternSize = patternData.count

    if size <= patternSize {
      return Data(patternData.prefix(size))
    }

    var result = Data()
    result.reserveCapacity(size)

    let fullRepeats = size / patternSize
    let remainder = size % patternSize

    for _ in 0..<fullRepeats {
      result.append(patternData)
    }

    if remainder > 0 {
      result.append(patternData.prefix(remainder))
    }

    return result
  }
}

extension URL {
  func mimeType() -> String? {
    guard let uti = UTType(filenameExtension: self.pathExtension) else {
      return nil
    }
    return uti.preferredMIMEType
  }
}

#Preview {
  StorageUploadView(
    bucket: Bucket(
      id: UUID().uuidString,
      name: "test-bucket",
      owner: "owner",
      isPublic: false,
      createdAt: Date(),
      updatedAt: Date(),
      allowedMimeTypes: nil,
      fileSizeLimit: nil
    )
  )
}
