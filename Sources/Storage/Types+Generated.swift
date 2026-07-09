import Foundation

extension Bucket {
  init(generated: BucketSchema) {
    self.init(
      id: generated.id, name: generated.name, owner: generated.owner ?? "",
      isPublic: generated.public ?? false,
      createdAt: generated.createdAt.flatMap { $0.date } ?? Date(timeIntervalSince1970: 0),
      updatedAt: generated.updatedAt.flatMap { $0.date } ?? Date(timeIntervalSince1970: 0),
      allowedMimeTypes: generated.allowedMimeTypes,
      fileSizeLimit: generated.fileSizeLimit.map(Int64.init)
    )
  }
}
