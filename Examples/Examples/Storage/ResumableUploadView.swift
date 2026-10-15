//
//  ResumableUploadView.swift
//  Examples
//
//  Resumable (tus) uploads with pause, resume, cancel, and continuation after a relaunch.
//

import PhotosUI
import Supabase
import SwiftUI

/// Mirrors one ``ResumableUpload`` for SwiftUI and keeps the app alive for a short while when
/// it goes to the background mid-upload.
@Observable @MainActor
final class ResumableUploadModel {
  private(set) var upload: ResumableUpload?
  private(set) var state: ResumableUpload.State = .pending
  private(set) var progress: TransferProgress?
  private(set) var pending: [ResumableUpload] = []
  var error: Error?

  private var observers: [Task<Void, Never>] = []
  private var backgroundTask: UIBackgroundTaskIdentifier = .invalid

  var isActive: Bool {
    switch state {
    case .pending, .uploading, .paused: upload != nil
    case .completed, .failed, .cancelled: false
    }
  }

  func start(_ make: () throws -> ResumableUpload) async {
    do {
      error = nil
      let upload = try make()
      track(upload)
      try await upload.start()
    } catch {
      self.error = error
    }
    refreshPending()
  }

  func pause() async {
    await upload?.pause()
  }

  /// A handle restored from disk is `.pending` until `start()`; after that `resume()` is the
  /// call that continues a paused or failed upload.
  func resume() async {
    guard let upload else { return }
    do {
      if case .pending = await upload.state {
        try await upload.start()
      } else {
        try await upload.resume()
      }
    } catch {
      self.error = error
    }
  }

  func cancel() async {
    await upload?.cancel()
    refreshPending()
  }

  /// Picks a pending upload back up, for example one created before the last relaunch.
  func resume(_ pending: ResumableUpload) async {
    track(pending)
    await resume()
  }

  func refreshPending() {
    do {
      pending = try supabase.storage.resumableUploads.pending()
    } catch {
      self.error = error
    }
  }

  private func track(_ upload: ResumableUpload) {
    observers.forEach { $0.cancel() }
    self.upload = upload
    progress = nil
    observers = [
      Task { [weak self] in
        for await state in upload.states {
          guard let self else { return }
          self.state = state
          extendBackgroundExecution(while: state)
        }
      },
      Task { [weak self] in
        for await progress in upload.progress {
          self?.progress = progress
        }
      },
    ]
  }

  /// Asks iOS for a short extension while a chunk is in flight, so a user who backgrounds the
  /// app mid-chunk does not lose it; the SDK resumes from the last confirmed offset either way.
  private func extendBackgroundExecution(while state: ResumableUpload.State) {
    if case .uploading = state {
      guard backgroundTask == .invalid else { return }
      backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "resumable-upload") {
        [weak self] in
        Task { await self?.pause() }
      }
    } else if backgroundTask != .invalid {
      UIApplication.shared.endBackgroundTask(backgroundTask)
      backgroundTask = .invalid
    }
  }
}

/// A picked photo or video staged as a file, so a large video never sits in memory whole; the
/// SDK copies it into its own store during `start()`.
struct PickedFile: Transferable {
  let url: URL

  static var transferRepresentation: some TransferRepresentation {
    FileRepresentation(importedContentType: .movie) { try PickedFile(staging: $0.file) }
    FileRepresentation(importedContentType: .image) { try PickedFile(staging: $0.file) }
  }

  private init(staging received: URL) throws {
    url = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString)
      .appendingPathExtension(received.pathExtension)
    try FileManager.default.copyItem(at: received, to: url)
  }
}

struct ResumableUploadView: View {
  @State private var model = ResumableUploadModel()
  @State private var buckets: [Bucket] = []
  @State private var selectedBucket = ""
  @State private var filePath = ""
  @State private var selectedPhoto: PhotosPickerItem?
  @State private var isImporting = false

  var body: some View {
    List {
      Section {
        Text("Large uploads over tus: pause, resume, cancel, and continue after a relaunch.")
          .font(.caption)
          .foregroundColor(.secondary)
      }

      Section("Select Bucket") {
        Picker("Bucket", selection: $selectedBucket) {
          Text("Select a bucket").tag("")
          ForEach(buckets) { bucket in
            Text(bucket.name).tag(bucket.id)
          }
        }
        TextField("File path (e.g., videos/clip.mov)", text: $filePath)
          .textInputAutocapitalization(.never)
      }

      Section("Source") {
        PhotosPicker(selection: $selectedPhoto, matching: .any(of: [.images, .videos])) {
          Label("Upload from Photo Library", systemImage: "photo.on.rectangle")
        }
        Button {
          isImporting = true
        } label: {
          Label("Upload a Document", systemImage: "doc")
        }
      }
      .disabled(selectedBucket.isEmpty || filePath.isEmpty || model.isActive)

      if let upload = model.upload {
        Section("Transfer") {
          VStack(alignment: .leading, spacing: 8) {
            Text("\(upload.bucketId)/\(upload.path)")
              .font(.caption)
            ProgressView(value: model.progress?.fractionCompleted ?? 0)
            Text(
              "\(stateLabel) — \(formatBytes(model.progress?.completedBytes ?? 0)) of \(formatBytes(upload.totalBytes))"
            )
            .font(.caption)
            .foregroundColor(.secondary)
          }

          HStack {
            switch model.state {
            case .uploading:
              Button("Pause") { Task { await model.pause() } }
            case .paused, .pending:
              Button("Resume") { Task { await model.resume() } }
            case .completed, .failed, .cancelled:
              EmptyView()
            }
            Spacer()
            if model.isActive {
              Button("Cancel", role: .destructive) { Task { await model.cancel() } }
            }
          }
        }
      }

      if !model.pending.isEmpty {
        Section("Pending Uploads") {
          ForEach(model.pending, id: \.id) { pending in
            Button {
              Task { await model.resume(pending) }
            } label: {
              VStack(alignment: .leading) {
                Text("\(pending.bucketId)/\(pending.path)")
                Text(formatBytes(pending.totalBytes))
                  .font(.caption)
                  .foregroundColor(.secondary)
              }
            }
            .disabled(model.isActive)
          }
        }
      }

      if let error = model.error {
        Section {
          ErrorText(error)
        }
      }
    }
    .navigationTitle("Resumable Upload")
    .gitHubSourceLink()
    .task {
      model.refreshPending()
      do {
        buckets = try await supabase.storage.listBuckets()
        selectedBucket = buckets.first?.id ?? ""
      } catch {
        model.error = error
      }
    }
    .onChange(of: selectedPhoto) { _, item in
      guard let item else { return }
      Task {
        guard let picked = try? await item.loadTransferable(type: PickedFile.self) else { return }
        selectedPhoto = nil
        await model.start {
          try supabase.storage.from(selectedBucket)
            .resumableUpload(path: filePath, fileURL: picked.url)
        }
        try? FileManager.default.removeItem(at: picked.url)
      }
    }
    .fileImporter(isPresented: $isImporting, allowedContentTypes: [.item]) { result in
      guard case .success(let url) = result else { return }
      Task {
        // The SDK copies the file into its store during `start()`, so the security scope only
        // needs to stay open until then.
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        await model.start {
          try supabase.storage.from(selectedBucket).resumableUpload(path: filePath, fileURL: url)
        }
      }
    }
  }

  private var stateLabel: String {
    switch model.state {
    case .pending: "Pending"
    case .uploading: "Uploading"
    case .paused: "Paused"
    case .completed: "Completed"
    case .failed(let error): "Failed: \(error.message)"
    case .cancelled: "Cancelled"
    }
  }

  private func formatBytes(_ count: Int64) -> String {
    ByteCountFormatter.string(fromByteCount: count, countStyle: .file)
  }
}
