#if canImport(CoreTransferable) && canImport(UniformTypeIdentifiers)
  import ConcurrencyExtras
  public import CoreTransferable
  import Foundation
  public import UniformTypeIdentifiers

  extension StorageBucket {
    /// Uploads a `Transferable` value, such as an app model or a drag-and-drop payload, to an
    /// existing bucket.
    ///
    /// The item is exported as `contentType` to a temporary file, which is uploaded the same way
    /// as ``upload(path:fileURL:options:progress:)`` and deleted afterwards.
    ///
    /// ```swift
    /// struct Report: Transferable {
    ///   var pdf: Data
    ///
    ///   static var transferRepresentation: some TransferRepresentation {
    ///     DataRepresentation(exportedContentType: .pdf) { $0.pdf }
    ///   }
    /// }
    ///
    /// try await storage.from("reports").upload(path: "q3.pdf", item: report, contentType: .pdf)
    /// ```
    ///
    /// A `PhotosPickerItem` is not `Transferable` itself. Load it as a type that imports a file,
    /// and upload that file with ``upload(path:fileURL:options:progress:)``.
    ///
    /// - Parameters:
    ///   - path: The relative file path within the bucket, e.g. `"folder/subfolder/filename.png"`.
    ///     The bucket must already exist before attempting to upload.
    ///   - item: The item to upload. It must export `contentType`.
    ///   - contentType: The type to export the item as. Its preferred MIME type is the object's
    ///     `Content-Type` unless `options` sets one.
    ///   - options: Upload options such as cache control, content type, and upsert behavior.
    ///   - progress: Called as the bytes are sent; see ``TransferProgress``.
    /// - Returns: An ``UploadedObject`` containing the stored object's identifier and path.
    /// - Throws: ``StorageError`` with ``StorageError/Kind/invalidRequest`` if the item cannot be
    ///   exported as `contentType`, or ``StorageError`` if the upload fails.
    @discardableResult
    public func upload(
      path: String,
      item: some Transferable,
      contentType: UTType,
      options: UploadOptions = UploadOptions(),
      progress: (@Sendable (TransferProgress) -> Void)? = nil
    ) async throws -> UploadedObject {
      let fileURL = try await exportFile(item, as: contentType)
      defer { try? FileManager.default.removeItem(at: fileURL) }

      var options = options
      options.contentType = options.contentType ?? contentType.preferredMIMEType
      return try await upload(path: path, fileURL: fileURL, options: options, progress: progress)
    }
  }

  /// Exports `item` to a temporary file the caller owns.
  ///
  /// `Transferable`'s own export methods need iOS 18.2, so this goes through `NSItemProvider`,
  /// which works from iOS 16.
  private func exportFile(_ item: some Transferable, as contentType: UTType) async throws -> URL {
    let provider = NSItemProvider()
    provider.register(item)

    let exportFailed: @Sendable ((any Error)?) -> StorageError = { error in
      StorageError(
        kind: .invalidRequest,
        message: "The item cannot be exported as \(contentType.identifier).",
        underlyingError: error)
    }

    guard provider.hasItemConformingToTypeIdentifier(contentType.identifier) else {
      throw exportFailed(nil)
    }

    let loading = LockIsolated<Progress?>(nil)
    do {
      return try await withTaskCancellationHandler {
        try await withCheckedThrowingContinuation { continuation in
          let progress = provider.loadFileRepresentation(
            forTypeIdentifier: contentType.identifier
          ) { url, error in
            guard let url else {
              continuation.resume(throwing: exportFailed(error))
              return
            }
            // The provider deletes `url` when this handler returns.
            let destination = FileManager.default.temporaryDirectory
              .appending(path: UUID().uuidString)
              .appendingPathExtension(contentType.preferredFilenameExtension ?? url.pathExtension)
            do {
              if (try? FileManager.default.moveItem(at: url, to: destination)) == nil {
                try FileManager.default.copyItem(at: url, to: destination)
              }
              continuation.resume(returning: destination)
            } catch {
              continuation.resume(throwing: exportFailed(error))
            }
          }
          loading.setValue(progress)
        }
      } onCancel: {
        loading.value?.cancel()
      }
    } catch  where Task.isCancelled {
      throw CancellationError()
    }
  }
#endif
