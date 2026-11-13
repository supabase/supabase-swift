import Foundation
import Supabase

/// All calls for reminder images: the `reminder_attachments` table and the private
/// `attachments` Storage bucket.
///
/// A file path is `{reminder id}/{file id}.jpg`. The Storage policies read the reminder
/// id from the path to decide who can open the file.
struct AttachmentsRepository: Sendable {
  let client: SupabaseClient

  private static let bucket = "attachments"

  func fetchAll() async throws -> [Attachment] {
    try await client.from("reminder_attachments")
      .select()
      .order("created_at")
      .execute()
      .value
  }

  /// Uploads the file, then saves the row. If the row fails, the file is removed.
  func upload(jpeg: Data, reminderID: UUID) async throws -> Attachment {
    let path = "\(reminderID.uuidString.lowercased())/\(UUID().uuidString.lowercased()).jpg"
    try await client.storage.from(Self.bucket)
      .upload(path, data: jpeg, options: FileOptions(contentType: "image/jpeg"))

    do {
      return try await client.from("reminder_attachments")
        .insert(["reminder_id": reminderID.uuidString, "storage_path": path])
        .select()
        .single()
        .execute()
        .value
    } catch {
      try? await deleteObjects(paths: [path])
      throw error
    }
  }

  func download(path: String) async throws -> Data {
    try await client.storage.from(Self.bucket).download(path: path)
  }

  /// Removes the file, then the row.
  func delete(_ attachment: Attachment) async throws {
    try await deleteObjects(paths: [attachment.storagePath])
    try await client.from("reminder_attachments")
      .delete()
      .eq("id", value: attachment.id)
      .execute()
  }

  /// Removes files from the bucket.
  ///
  /// The database deletes attachment rows by cascade when a reminder or a list goes
  /// away. It cannot delete the files, so the app removes them first.
  func deleteObjects(paths: [String]) async throws {
    guard !paths.isEmpty else { return }
    try await client.storage.from(Self.bucket).remove(paths: paths)
  }
}
