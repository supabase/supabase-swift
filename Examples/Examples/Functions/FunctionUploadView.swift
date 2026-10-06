//
//  FunctionUploadView.swift
//  Examples
//
//  Streams a file from disk to an Edge Function.
//

import PhotosUI
import Supabase
import SwiftUI

struct FunctionUploadView: View {
  @State private var selectedImage: PhotosPickerItem?
  @State private var fileURL: URL?
  @State private var result: UploadResult?
  @State private var error: Error?
  @State private var isUploading = false

  var body: some View {
    List {
      Section {
        Text(
          "Send a file as the request body without loading it into memory, with a longer timeout for the transfer."
        )
        .font(.caption)
        .foregroundColor(.secondary)
      }

      Section("File") {
        PhotosPicker(selection: $selectedImage, matching: .images) {
          Label("Select Image", systemImage: "photo.on.rectangle")
        }

        if let fileURL {
          Text(fileURL.lastPathComponent)
            .font(.caption)
            .foregroundColor(.secondary)

          Button("Upload") {
            Task { await upload(fileURL) }
          }
          .disabled(isUploading)
        }

        if isUploading {
          ProgressView()
        }
      }

      if let result {
        Section("Function Response") {
          Text(
            "Received \(ByteCountFormatter.string(fromByteCount: Int64(result.bytes), countStyle: .file)) as \(result.contentType ?? "unknown type")"
          )
        }
      }

      if let error {
        Section {
          ErrorText(error)
        }
      }

      Section("Swift Code") {
        CodeExample(
          code: """
            try await supabase.functions.invoke(
              "upload",
              body: .stream(try HTTPBody(fileURL: fileURL), contentType: "image/jpeg"),
              options: .init(timeout: .seconds(300))
            )
            """)
      }
    }
    .navigationTitle("Upload a File")
    .gitHubSourceLink()
    .onChange(of: selectedImage) { _, newValue in
      Task {
        guard let data = try? await newValue?.loadTransferable(type: Data.self) else { return }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("upload.jpg")
        try? data.write(to: url)
        fileURL = url
      }
    }
  }

  @MainActor
  private func upload(_ fileURL: URL) async {
    do {
      error = nil
      result = nil
      isUploading = true
      defer { isUploading = false }

      result = try await supabase.functions.invoke(
        "upload",
        body: .stream(try HTTPBody(fileURL: fileURL), contentType: "image/jpeg"),
        options: .init(timeout: .seconds(300))
      )
    } catch {
      self.error = error
    }
  }

  private struct UploadResult: Decodable {
    let bytes: Int
    let contentType: String?
  }
}
