//
//  BucketConversions.swift
//  Storage
//
//  Created by Guilherme Souza on 30/06/25.
//

import Foundation

extension Bucket {
  /// Creates a ``Bucket`` from a generated ``Components/Schemas/Bucket`` value.
  init(generated: Components.Schemas.Bucket) {
    let formatter = ISO8601DateFormatter()
    self.init(
      id: generated.id,
      name: generated.name,
      owner: "",
      isPublic: generated._public,
      createdAt: generated.created_at.flatMap { formatter.date(from: $0) } ?? Date(),
      updatedAt: generated.updated_at.flatMap { formatter.date(from: $0) } ?? Date(),
      allowedMimeTypes: generated.allowed_mime_types,
      fileSizeLimit: generated.file_size_limit.map { Int64($0) }
    )
  }

  /// Creates a ``Bucket`` from a generated ``Components/Schemas/GetBucketResponseContent`` value.
  init(generated: Components.Schemas.GetBucketResponseContent) {
    let formatter = ISO8601DateFormatter()
    self.init(
      id: generated.id,
      name: generated.name,
      owner: "",
      isPublic: generated._public,
      createdAt: generated.created_at.flatMap { formatter.date(from: $0) } ?? Date(),
      updatedAt: generated.updated_at.flatMap { formatter.date(from: $0) } ?? Date(),
      allowedMimeTypes: generated.allowed_mime_types,
      fileSizeLimit: generated.file_size_limit.map { Int64($0) }
    )
  }
}
