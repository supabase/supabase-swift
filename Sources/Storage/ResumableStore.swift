//
//  ResumableStore.swift
//  Storage
//
//  Created by Guilherme Souza on 15/10/26.
//

import Crypto
import Foundation
import Helpers

/// Where the bytes of a resumable upload are read from.
enum ResumableSource: Hashable, Codable, Sendable {
  /// A file inside the app container, used in place and addressed relative to the container so
  /// the record survives the container moving between launches.
  case container(relativePath: String)
  /// A copy the store owns, at `<fingerprint>.bin` in its directory.
  case sandboxCopy
}

/// Everything needed to continue an upload after a relaunch: what is uploaded, where on the
/// server, and how far it got.
struct ResumableUploadRecord: Hashable, Codable, Sendable {
  let fingerprint: String
  let bucketId: String
  let path: String
  let totalBytes: Int64
  let source: ResumableSource
  let sourceModificationDate: Date
  var uploadURL: URL
  let createdAt: Date
  var expiresAt: Date
  var lastKnownOffset: Int64
  let chunkSize: Int64
  let upsert: Bool
  let contentType: String?
  let cacheControl: String
  let metadata: JSONObject?
}

/// One JSON file per in-flight resumable upload, plus the sandbox copies of sources the app
/// cannot rely on finding again.
///
/// A record is stale, and removed on the next read, once it has expired or once its source no
/// longer matches the size and modification date it was created with.
struct ResumableStore: Sendable {
  /// Where the records and sandbox copies live.
  let directory: URL
  private let container: URL
  private let temporaryDirectory: URL
  private let now: @Sendable () -> Date

  /// How long a record lives when the server sends no `Upload-Expires`.
  static let defaultLifetime: TimeInterval = 24 * 60 * 60

  init(
    directory: URL = FileManager.default.urls(
      for: .applicationSupportDirectory, in: .userDomainMask)[0]
      .appendingPathComponent("io.supabase.storage/resumable", isDirectory: true),
    container: URL = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true),
    temporaryDirectory: URL = FileManager.default.temporaryDirectory,
    now: @escaping @Sendable () -> Date = Date.init
  ) {
    self.directory = directory
    self.container = container.standardizedFileURL
    self.temporaryDirectory = temporaryDirectory.standardizedFileURL
    self.now = now
  }

  // MARK: - Fingerprint

  /// SHA-256 of the bucket, path, size and modification date, so the same file picked twice
  /// through different temporary URLs is the same upload.
  static func fingerprint(bucketId: String, path: String, fileURL: URL) throws -> String {
    let attributes = try FileManager.default.attributesOfItem(atPath: fileURL.path)
    let size = (attributes[.size] as? NSNumber)?.int64Value ?? 0
    let modified = (attributes[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
    return fingerprint("\(bucketId)\n\(path)\n\(size)\n\(modified)")
  }

  static func fingerprint(bucketId: String, path: String, data: Data) -> String {
    fingerprint("\(bucketId)\n\(path)\n\(data.count)\n\(hex(SHA256.hash(data: data)))")
  }

  private static func fingerprint(_ input: String) -> String {
    hex(SHA256.hash(data: Data(input.utf8)))
  }

  private static func hex(_ digest: SHA256.Digest) -> String {
    digest.map { String(format: "%02x", $0) }.joined()
  }

  // MARK: - Sources

  /// Uses `fileURL` in place when it sits in the app container outside its temporary directory;
  /// otherwise copies it into the store, since picker and `Transferable` URLs do not outlive the
  /// process.
  @concurrent
  func prepare(fileURL: URL, fingerprint: String) async throws -> ResumableSource {
    let path = fileURL.standardizedFileURL.path
    if path.hasPrefix(container.path + "/"), !path.hasPrefix(temporaryDirectory.path + "/") {
      return .container(relativePath: String(path.dropFirst(container.path.count + 1)))
    }
    let copy = sandboxCopyURL(fingerprint: fingerprint)
    try createDirectory()
    try? FileManager.default.removeItem(at: copy)
    try FileManager.default.copyItem(at: fileURL, to: copy)
    return .sandboxCopy
  }

  func prepare(data: Data, fingerprint: String) throws -> ResumableSource {
    try createDirectory()
    try data.write(to: sandboxCopyURL(fingerprint: fingerprint), options: .atomic)
    return .sandboxCopy
  }

  func fileURL(for record: ResumableUploadRecord) -> URL {
    switch record.source {
    case .container(let relativePath):
      container.appendingPathComponent(relativePath)
    case .sandboxCopy:
      sandboxCopyURL(fingerprint: record.fingerprint)
    }
  }

  // MARK: - Records

  func save(_ record: ResumableUploadRecord) throws {
    try createDirectory()
    try Self.encoder.encode(record).write(
      to: recordURL(fingerprint: record.fingerprint), options: .atomic)
  }

  /// The record, or `nil` when there is none or it is stale (a stale one is removed).
  func record(fingerprint: String) throws -> ResumableUploadRecord? {
    let url = recordURL(fingerprint: fingerprint)
    guard FileManager.default.fileExists(atPath: url.path) else { return nil }
    let record = try Self.decoder.decode(ResumableUploadRecord.self, from: Data(contentsOf: url))
    guard !isStale(record) else {
      try remove(record)
      return nil
    }
    return record
  }

  /// Every live record, oldest first. Stale ones are removed on the way.
  func records() throws -> [ResumableUploadRecord] {
    guard FileManager.default.fileExists(atPath: directory.path) else { return [] }
    return try FileManager.default.contentsOfDirectory(atPath: directory.path)
      .filter { $0.hasSuffix(".json") }
      .compactMap { try record(fingerprint: String($0.dropLast(".json".count))) }
      .sorted { $0.createdAt < $1.createdAt }
  }

  func remove(_ record: ResumableUploadRecord) throws {
    try? FileManager.default.removeItem(at: recordURL(fingerprint: record.fingerprint))
    if record.source == .sandboxCopy {
      try? FileManager.default.removeItem(at: sandboxCopyURL(fingerprint: record.fingerprint))
    }
  }

  func removeAll() throws {
    guard FileManager.default.fileExists(atPath: directory.path) else { return }
    try FileManager.default.removeItem(at: directory)
  }

  private func isStale(_ record: ResumableUploadRecord) -> Bool {
    guard record.expiresAt > now(),
      let attributes = try? FileManager.default.attributesOfItem(atPath: fileURL(for: record).path),
      (attributes[.size] as? NSNumber)?.int64Value == record.totalBytes
    else { return true }
    guard case .container = record.source else { return false }
    let modified = (attributes[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
    return abs(modified - record.sourceModificationDate.timeIntervalSince1970) > 0.001
  }

  private func recordURL(fingerprint: String) -> URL {
    directory.appendingPathComponent("\(fingerprint).json")
  }

  private func sandboxCopyURL(fingerprint: String) -> URL {
    directory.appendingPathComponent("\(fingerprint).bin")
  }

  private func createDirectory() throws {
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
  }

  /// Dates as epoch seconds, so they round-trip exactly.
  private static let encoder: JSONEncoder = {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .secondsSince1970
    return encoder
  }()

  private static let decoder: JSONDecoder = {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .secondsSince1970
    return decoder
  }()
}
