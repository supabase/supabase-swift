//
//  FileUploadView.swift
//  Examples
//
//  Created by Guilherme Souza on 06/05/25.
//
//  Demonstrates all three upload engines:
//    - Smart (auto): multipart for files ≤6 MB, TUS for larger files
//    - Multipart: standard HTTP multipart, always
//    - Resumable (TUS): pause / resume / cancel support, ideal for large files
//

import PhotosUI
import Supabase
import SwiftUI
import UniformTypeIdentifiers

struct FileUploadView: View {

  // MARK: - Upload mode

  enum UploadMode: String, CaseIterable, Identifiable {
    case auto = "Smart"
    case multipart = "Multipart"
    case resumable = "Resumable"

    var id: Self { self }

    var description: String {
      switch self {
      case .auto:
        return "Auto-selects multipart for files \u{2264}6 MB and TUS for larger files."
      case .multipart:
        return "Standard HTTP multipart upload \u{2014} always multipart regardless of size."
      case .resumable:
        return "TUS 1.0.0 resumable upload with pause, resume, and cancel. Ideal for large files."
      }
    }

    var method: UploadMethod {
      switch self {
      case .auto: return .auto
      case .multipart: return .multipart
      case .resumable: return .resumable
      }
    }
  }

  // MARK: - State

  @State private var selectedBucket = ""
  @State private var buckets: [Bucket] = []
  @State private var filePath = ""
  @State private var upsertEnabled = false
  @State private var cacheControl = "3600"
  @State private var uploadMode: UploadMode = .auto

  // Photo picker
  @State private var selectedImage: PhotosPickerItem?
  @State private var imageData: Data?

  // Document picker
  @State private var selectedDocument: URL?
  @State private var isShowingDocumentPicker = false

  // Transfer state
  @State private var isUploading = false
  @State private var isPaused = false
  @State private var uploadProgress: Double = 0
  @State private var uploadedPath: String?
  @State private var error: Error?

  // Hold a reference so we can pause / resume / cancel
  @State private var currentTask: StorageUploadTask?

  // MARK: - Body

  var body: some View {
    List {
      descriptionSection
      methodSection
      bucketSection
      optionsSection
      photoSection
      documentSection
      sampleTextSection

      if isUploading || isPaused {
        transferSection
      }

      if let uploadedPath {
        successSection(path: uploadedPath)
      }

      if let error {
        Section { ErrorText(error) }
      }
    }
    .navigationTitle("Upload Files")
    .gitHubSourceLink()
    .task { await loadBuckets() }
    .onChange(of: selectedImage) { _, newValue in
      Task {
        imageData = try? await newValue?.loadTransferable(type: Data.self)
      }
    }
    .sheet(isPresented: $isShowingDocumentPicker) {
      DocumentPicker(selectedURL: $selectedDocument)
    }
  }

  // MARK: - Sections

  private var descriptionSection: some View {
    Section {
      Text("Upload files using the smart default, explicit multipart, or TUS resumable protocol.")
        .font(.caption)
        .foregroundColor(.secondary)
    }
  }

  private var methodSection: some View {
    Section("Upload Method") {
      Picker("Method", selection: $uploadMode) {
        ForEach(UploadMode.allCases) { mode in
          Text(mode.rawValue).tag(mode)
        }
      }
      .pickerStyle(.segmented)

      Text(uploadMode.description)
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

      TextField("File path (e.g., folder/image.jpg)", text: $filePath)
        .textInputAutocapitalization(.never)
        .autocorrectionDisabled()
    }
  }

  private var optionsSection: some View {
    Section("Upload Options") {
      Toggle("Upsert (overwrite if exists)", isOn: $upsertEnabled)

      HStack {
        Text("Cache Control (seconds)")
        Spacer()
        TextField("3600", text: $cacheControl)
          .keyboardType(.numberPad)
          .multilineTextAlignment(.trailing)
          .frame(width: 80)
      }
    }
  }

  private var photoSection: some View {
    Section("Photo Library") {
      PhotosPicker(selection: $selectedImage, matching: .images) {
        Label("Select Image", systemImage: "photo.on.rectangle")
      }

      if let imageData {
        HStack {
          Image(systemName: "checkmark.circle.fill").foregroundColor(.green)
          Text(
            "Image selected (\(ByteCountFormatter.string(fromByteCount: Int64(imageData.count), countStyle: .file)))"
          )
        }

        Button("Upload Image") {
          Task { await uploadData(imageData, contentType: "image/jpeg") }
        }
        .disabled(selectedBucket.isEmpty || filePath.isEmpty || isUploading || isPaused)
      }
    }
  }

  private var documentSection: some View {
    Section("Document") {
      Button("Select Document") {
        isShowingDocumentPicker = true
      }

      if let selectedDocument {
        HStack {
          Image(systemName: "checkmark.circle.fill").foregroundColor(.green)
          Text(selectedDocument.lastPathComponent)
            .lineLimit(1)
        }

        Button("Upload Document") {
          Task { await uploadFileURL(selectedDocument) }
        }
        .disabled(selectedBucket.isEmpty || filePath.isEmpty || isUploading || isPaused)
      }
    }
  }

  private var sampleTextSection: some View {
    Section("Quick Test") {
      Button("Upload Sample Text File") {
        Task { await uploadSampleText() }
      }
      .disabled(selectedBucket.isEmpty || filePath.isEmpty || isUploading || isPaused)
    }
  }

  private var transferSection: some View {
    Section("Transfer") {
      // Progress row
      VStack(spacing: 6) {
        ProgressView(value: uploadProgress)
        HStack {
          Text(isPaused ? "Paused" : "Uploading…")
          Spacer()
          Text("\(Int(uploadProgress * 100))%")
        }
        .font(.caption)
        .foregroundColor(.secondary)
      }
      .padding(.vertical, 4)

      // Control row — separate list row so it is never clipped
      if uploadMode == .resumable {
        HStack(spacing: 12) {
          if isPaused {
            Button("Resume") {
              Task { await resumeUpload() }
            }
            .buttonStyle(.borderedProminent)
          } else {
            Button("Pause") {
              Task { await pauseUpload() }
            }
            .buttonStyle(.bordered)
          }

          Spacer()

          Button("Cancel", role: .destructive) {
            Task { await cancelUpload() }
          }
          .buttonStyle(.bordered)
        }
      }
    }
  }

  private func successSection(path: String) -> some View {
    Section("Success") {
      VStack(alignment: .leading, spacing: 6) {
        Label("File uploaded successfully!", systemImage: "checkmark.circle.fill")
          .foregroundColor(.green)
        Text("Path: \(path)")
          .font(.caption)
          .foregroundColor(.secondary)
        Text("Engine: \(uploadMode.rawValue)")
          .font(.caption)
          .foregroundColor(.secondary)
      }
    }
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
  func uploadData(_ data: Data, contentType: String) async {
    let options = FileOptions(
      cacheControl: cacheControl,
      contentType: contentType,
      upsert: upsertEnabled
    )
    let task = supabase.storage.from(selectedBucket)
      .upload(filePath, data: data, options: options, method: uploadMode.method)
    await run(task) {
      self.imageData = nil
      self.selectedImage = nil
    }
  }

  @MainActor
  func uploadFileURL(_ fileURL: URL) async {
    let options = FileOptions(cacheControl: cacheControl, upsert: upsertEnabled)
    let task = supabase.storage.from(selectedBucket)
      .upload(filePath, fileURL: fileURL, options: options, method: uploadMode.method)
    await run(task) {
      self.selectedDocument = nil
    }
  }

  @MainActor
  func uploadSampleText() async {
    let text = "Sample text uploaded to Supabase Storage\nCreated at: \(Date())"
    let data = Data(text.utf8)
    await uploadData(data, contentType: "text/plain")
  }

  /// Drives a `StorageUploadTask`, updating progress state from the event stream.
  @MainActor
  func run(_ task: StorageUploadTask, onComplete: @escaping @MainActor () -> Void) async {
    error = nil
    uploadedPath = nil
    uploadProgress = 0
    isPaused = false
    isUploading = true
    currentTask = task

    for await event in task.events {
      switch event {
      case .progress(let p):
        // Only overwrite progress when not paused — the paused state is set by the user
        // action, not by the event stream.
        if !isPaused { uploadProgress = p.fractionCompleted }

      case .completed(let response):
        uploadProgress = 1.0
        uploadedPath = response.path
        filePath = ""
        onComplete()

      case .failed(let storageError):
        self.error = storageError
      }
    }

    isUploading = false
    isPaused = false
    currentTask = nil
  }

  @MainActor
  func pauseUpload() async {
    await currentTask?.pause()
    isPaused = true
  }

  @MainActor
  func resumeUpload() async {
    await currentTask?.resume()
    isPaused = false
  }

  @MainActor
  func cancelUpload() async {
    await currentTask?.cancel()
    isUploading = false
    isPaused = false
    uploadProgress = 0
    currentTask = nil
  }
}

// MARK: - DocumentPicker

struct DocumentPicker: UIViewControllerRepresentable {
  @Binding var selectedURL: URL?

  func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
    let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.item])
    picker.delegate = context.coordinator
    return picker
  }

  func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context)
  {}

  func makeCoordinator() -> Coordinator { Coordinator(self) }

  final class Coordinator: NSObject, UIDocumentPickerDelegate {
    let parent: DocumentPicker
    init(_ parent: DocumentPicker) { self.parent = parent }

    func documentPicker(
      _ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]
    ) {
      parent.selectedURL = urls.first
    }
  }
}
