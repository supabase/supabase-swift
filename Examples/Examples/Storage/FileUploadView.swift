//
//  FileUploadView.swift
//  Examples
//
//  Demonstrates various file upload methods and options
//

import PhotosUI
import Supabase
import SwiftUI
import UniformTypeIdentifiers

struct FileUploadView: View {
  @State private var selectedBucket = ""
  @State private var buckets: [Bucket] = []
  @State private var filePath = ""
  @State private var selectedImage: PhotosPickerItem?
  @State private var imageData: Data?
  @State private var selectedDocument: URL?
  @State private var isShowingDocumentPicker = false
  @State private var uploadProgress: Double = 0
  @State private var isUploading = false
  @State private var uploadedPath: String?
  @State private var error: Error?
  @State private var upsertEnabled = false
  @State private var cacheControl = "3600"

  var body: some View {
    List {
      Section {
        Text("Upload files to Supabase Storage with various options")
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

        TextField("File path (e.g., folder/image.jpg)", text: $filePath)
          .textInputAutocapitalization(.never)
      }

      Section("Upload Options") {
        Toggle("Upsert (overwrite if exists)", isOn: $upsertEnabled)

        HStack {
          Text("Cache Control (seconds)")
          TextField("3600", text: $cacheControl)
            .keyboardType(.numberPad)
            .multilineTextAlignment(.trailing)
        }
      }

      Section("Upload from Photo Library") {
        PhotosPicker(selection: $selectedImage, matching: .images) {
          Label("Select Image", systemImage: "photo.on.rectangle")
        }

        if let imageData {
          HStack {
            Image(systemName: "checkmark.circle.fill")
              .foregroundColor(.green)
            Text(
              "Image selected (\(ByteCountFormatter.string(fromByteCount: Int64(imageData.count), countStyle: .file)))"
            )
          }

          Button("Upload Image") {
            Task {
              await uploadImage()
            }
          }
          .disabled(selectedBucket.isEmpty || filePath.isEmpty || isUploading)
        }
      }

      Section("Upload Document") {
        Button("Select Document") {
          isShowingDocumentPicker = true
        }

        if let selectedDocument {
          HStack {
            Image(systemName: "checkmark.circle.fill")
              .foregroundColor(.green)
            Text(selectedDocument.lastPathComponent)
          }

          Button("Upload Document") {
            Task {
              await uploadDocument()
            }
          }
          .disabled(selectedBucket.isEmpty || filePath.isEmpty || isUploading)
        }
      }

      Section("Upload Sample Text File") {
        Button("Upload Sample Text") {
          Task {
            await uploadSampleText()
          }
        }
        .disabled(selectedBucket.isEmpty || filePath.isEmpty || isUploading)
      }

      if isUploading {
        Section {
          VStack(spacing: 8) {
            ProgressView(value: uploadProgress)
            Text("Uploading... \(Int(uploadProgress * 100))%")
              .font(.caption)
              .foregroundColor(.secondary)
          }
        }
      }

      if let uploadedPath {
        Section("Success") {
          VStack(alignment: .leading, spacing: 4) {
            Text("File uploaded successfully!")
              .foregroundColor(.green)
            Text("Path: \(uploadedPath)")
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

      Section("Code Examples") {
        CodeExample(
          code: """
            // Upload from Data
            let data = "Hello, Storage!".data(using: .utf8)!
            let response = try await supabase.storage
              .from("my-bucket")
              .upload(
                "folder/file.txt",
                data: data,
                options: FileOptions(
                  cacheControl: "3600",
                  upsert: true
                )
              )

            print("Uploaded to:", response.path)
            """
        )

        CodeExample(
          code: """
            // Upload from file URL
            let fileURL = URL(fileURLWithPath: "/path/to/file.jpg")
            try await supabase.storage
              .from("my-bucket")
              .upload(
                "images/photo.jpg",
                fileURL: fileURL,
                options: FileOptions(
                  contentType: "image/jpeg",
                  upsert: false
                )
              )
            """
        )

        CodeExample(
          code: """
            // Update existing file
            try await supabase.storage
              .from("my-bucket")
              .update(
                "folder/file.txt",
                data: updatedData,
                options: FileOptions(cacheControl: "7200")
              )
            """
        )
      }
    }
    .navigationTitle("Upload Files")
    .task {
      await loadBuckets()
    }
    .onChange(of: selectedImage) { _, newValue in
      Task {
        if let data = try? await newValue?.loadTransferable(type: Data.self) {
          imageData = data
        }
      }
    }
    .sheet(isPresented: $isShowingDocumentPicker) {
      DocumentPicker(selectedURL: $selectedDocument)
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
  func uploadImage() async {
    guard let imageData else { return }

    do {
      error = nil
      uploadedPath = nil
      isUploading = true
      uploadProgress = 0

      let options = FileOptions(
        cacheControl: cacheControl,
        contentType: "image/jpeg",
        upsert: upsertEnabled
      )

      // Simulate progress
      for i in 1...3 {
        uploadProgress = Double(i) / 3.0
        try await Task.sleep(nanoseconds: 200_000_000)
      }

      let response = try await supabase.storage
        .from(selectedBucket)
        .upload(filePath, data: imageData, options: options)

      uploadedPath = response.path
      uploadProgress = 1.0

      // Reset
      selectedImage = nil
      self.imageData = nil
      filePath = ""
    } catch {
      self.error = error
    }

    isUploading = false
  }

  @MainActor
  func uploadDocument() async {
    guard let selectedDocument else { return }

    do {
      error = nil
      uploadedPath = nil
      isUploading = true
      uploadProgress = 0

      let options = FileOptions(
        cacheControl: cacheControl,
        upsert: upsertEnabled
      )

      for i in 1...3 {
        uploadProgress = Double(i) / 3.0
        try await Task.sleep(nanoseconds: 200_000_000)
      }

      let response = try await supabase.storage
        .from(selectedBucket)
        .upload(filePath, fileURL: selectedDocument, options: options)

      uploadedPath = response.path
      uploadProgress = 1.0

      self.selectedDocument = nil
      filePath = ""
    } catch {
      self.error = error
    }

    isUploading = false
  }

  @MainActor
  func uploadSampleText() async {
    do {
      error = nil
      uploadedPath = nil
      isUploading = true
      uploadProgress = 0

      let sampleText = """
        This is a sample text file uploaded to Supabase Storage!
        Created at: \(Date())
        """

      let data = sampleText.data(using: .utf8)!

      let options = FileOptions(
        cacheControl: cacheControl,
        contentType: "text/plain",
        upsert: upsertEnabled
      )

      for i in 1...3 {
        uploadProgress = Double(i) / 3.0
        try await Task.sleep(nanoseconds: 100_000_000)
      }

      let response = try await supabase.storage
        .from(selectedBucket)
        .upload(filePath, data: data, options: options)

      uploadedPath = response.path
      uploadProgress = 1.0
      filePath = ""
    } catch {
      self.error = error
    }

    isUploading = false
  }
}

struct DocumentPicker: UIViewControllerRepresentable {
  @Binding var selectedURL: URL?

  func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
    let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.item])
    picker.delegate = context.coordinator
    return picker
  }

  func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context)
  {
  }

  func makeCoordinator() -> Coordinator {
    Coordinator(self)
  }

  class Coordinator: NSObject, UIDocumentPickerDelegate {
    let parent: DocumentPicker

    init(_ parent: DocumentPicker) {
      self.parent = parent
    }

    func documentPicker(
      _ controller: UIDocumentPickerViewController,
      didPickDocumentsAt urls: [URL]
    ) {
      guard let url = urls.first else { return }
      parent.selectedURL = url
    }
  }
}
