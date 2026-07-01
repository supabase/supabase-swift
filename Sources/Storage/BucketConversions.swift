//
//  BucketConversions.swift
//  Storage
//
//  Created by Guilherme Souza on 30/06/25.
//

import Foundation

extension Bucket {
  /// Shared formatter; ISO8601DateFormatter is expensive to instantiate per call.
  /// Protected by the fact that `date(from:)` is documented as thread-safe on Apple platforms.
  private nonisolated(unsafe) static let iso8601: ISO8601DateFormatter = ISO8601DateFormatter()

  /// Creates a ``Bucket`` from a generated ``Components/Schemas/Bucket`` value.
  init(generated: Components.Schemas.Bucket) {
    self.init(
      id: generated.id,
      name: generated.name,
      // The generated Bucket schema does not include an `owner` field; use "" as the
      // zero-value sentinel so existing call-sites that ignore owner continue to work.
      owner: "",
      isPublic: generated._public,
      createdAt: generated.created_at.flatMap { Bucket.iso8601.date(from: $0) } ?? Date(),
      updatedAt: generated.updated_at.flatMap { Bucket.iso8601.date(from: $0) } ?? Date(),
      allowedMimeTypes: generated.allowed_mime_types,
      fileSizeLimit: generated.file_size_limit.map { Int64($0) }
    )
  }

  /// Creates a ``Bucket`` from a generated ``Components/Schemas/GetBucketResponseContent`` value.
  init(generated: Components.Schemas.GetBucketResponseContent) {
    self.init(
      id: generated.id,
      name: generated.name,
      // The generated GetBucketResponseContent schema does not include an `owner` field;
      // use "" as the zero-value sentinel.
      owner: "",
      isPublic: generated._public,
      createdAt: generated.created_at.flatMap { Bucket.iso8601.date(from: $0) } ?? Date(),
      updatedAt: generated.updated_at.flatMap { Bucket.iso8601.date(from: $0) } ?? Date(),
      allowedMimeTypes: generated.allowed_mime_types,
      fileSizeLimit: generated.file_size_limit.map { Int64($0) }
    )
  }
}
