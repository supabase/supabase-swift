import Foundation
import UIKit

// Images of reminders. None of these writes is optimistic: a file must reach Storage
// before other people can open it.
extension DataStore {
  func attachments(of reminderID: UUID) -> [Attachment] {
    attachments.filter { $0.reminderID == reminderID }
  }

  /// Makes the image smaller, uploads it, and saves the attachment row.
  ///
  /// - Parameter imageData: An image in a format that `UIImage` can read.
  func addAttachment(imageData: Data, reminderID: UUID) async throws {
    guard let jpeg = Self.jpeg(from: imageData) else { throw UnreadableImage() }
    let attachment = try await attachmentsRepository.upload(jpeg: jpeg, reminderID: reminderID)
    if let image = UIImage(data: jpeg) {
      imageCache.setObject(image, forKey: attachment.storagePath as NSString)
    }
    upsert(attachment, in: \.attachments)
  }

  func deleteAttachment(id: UUID) async throws {
    guard let attachment = attachments.first(where: { $0.id == id }) else { return }
    try await attachmentsRepository.delete(attachment)
    attachments.removeAll { $0.id == id }
  }

  /// The image of an attachment. It is downloaded one time and then kept in memory.
  func image(for attachment: Attachment) async throws -> UIImage {
    let key = attachment.storagePath as NSString
    if let cached = imageCache.object(forKey: key) { return cached }
    let data = try await attachmentsRepository.download(path: attachment.storagePath)
    guard let image = UIImage(data: data) else { throw UnreadableImage() }
    imageCache.setObject(image, forKey: key)
    return image
  }

  /// Removes the files of these reminders from Storage. Call it before the rows go away.
  func deleteFiles(ofReminders reminderIDs: Set<UUID>) async throws {
    let paths = attachments.filter { reminderIDs.contains($0.reminderID) }.map(\.storagePath)
    try await attachmentsRepository.deleteObjects(paths: paths)
  }

  /// A JPEG with a longest side of 2048 points at most. The bucket accepts files up to
  /// 5 MB, and a photo from the library can be larger.
  private static func jpeg(from data: Data) -> Data? {
    guard let image = UIImage(data: data) else { return nil }
    let longestSide = max(image.size.width, image.size.height)
    let scale = min(1, 2048 / longestSide)
    let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
    let format = UIGraphicsImageRendererFormat()
    format.scale = 1
    let resized = UIGraphicsImageRenderer(size: size, format: format).image { _ in
      image.draw(in: CGRect(origin: .zero, size: size))
    }
    return resized.jpegData(compressionQuality: 0.8)
  }
}

struct UnreadableImage: LocalizedError {
  var errorDescription: String? { "This image cannot be read." }
}
