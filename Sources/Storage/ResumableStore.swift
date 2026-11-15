//
//  ResumableStore.swift
//  Storage
//
//  Created by Guilherme Souza on 15/10/26.
//

import Crypto
import Foundation
import Helpers

/// The identity of one resumable upload: a hex SHA-256 digest, 64 lowercase hex characters.
///
/// The store names an upload's files `<fingerprint>.json` and `<fingerprint>.bin`, and only a
/// value that parses here can name one. So the store never builds a path from another string,
/// and never touches a file in its directory that it did not write.
struct Fingerprint: RawRepresentable, Hashable, Codable, Sendable {
  let rawValue: String

  /// Parses `rawValue`, or returns `nil` when it is not 64 lowercase hex characters.
  init?(rawValue: String) {
    guard
      rawValue.utf8.count == 64,
      rawValue.utf8.allSatisfy({
        (UInt8(ascii: "0")...UInt8(ascii: "9")).contains($0)
          || (UInt8(ascii: "a")...UInt8(ascii: "f")).contains($0)
      })
    else { return nil }
    self.rawValue = rawValue
  }

  /// Parses the fingerprint from a record file name, `<fingerprint>.json`, or returns `nil` for
  /// any other name.
  init?(recordFileName name: String) {
    guard name.hasSuffix(".json") else { return nil }
    self.init(rawValue: String(name.dropLast(".json".count)))
  }

  init(digest: SHA256.Digest) {
    rawValue = digest.hex
  }

  init(from decoder: any Decoder) throws {
    let container = try decoder.singleValueContainer()
    let rawValue = try container.decode(String.self)
    guard let fingerprint = Self(rawValue: rawValue) else {
      throw DecodingError.dataCorruptedError(
        in: container, debugDescription: "A fingerprint is 64 lowercase hex characters.")
    }
    self = fingerprint
  }

  func encode(to encoder: any Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(rawValue)
  }
}

extension SHA256.Digest {
  fileprivate var hex: String {
    map { String(format: "%02x", $0) }.joined()
  }
}

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
  let fingerprint: Fingerprint
  let bucketID: String
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

  init(configuration: ResumableUploadConfiguration) {
    if let directory = configuration.directory {
      self.init(directory: directory)
    } else {
      self.init()
    }
  }

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

  /// SHA-256 of the endpoint, bucket, path, size and modification date, so the same file picked
  /// twice through different temporary URLs is the same upload, and clients of two projects that
  /// share a record directory never share an upload.
  static func fingerprint(url: URL, bucketID: String, path: String, fileURL: URL) throws
    -> Fingerprint
  {
    let (size, modificationDate) = try attributes(of: fileURL)
    return fingerprint(
      "\(url.absoluteString)\n\(bucketID)\n\(path)\n\(size)\n\(modificationDate.timeIntervalSince1970)"
    )
  }

  static func fingerprint(url: URL, bucketID: String, path: String, data: Data) -> Fingerprint {
    fingerprint(
      "\(url.absoluteString)\n\(bucketID)\n\(path)\n\(data.count)\n\(SHA256.hash(data: data).hex)"
    )
  }

  private static func fingerprint(_ input: String) -> Fingerprint {
    Fingerprint(digest: SHA256.hash(data: Data(input.utf8)))
  }

  /// Uses `fileURL` in place when it sits in the app container outside its temporary directory;
  /// otherwise copies it into the store, since picker and `Transferable` URLs do not outlive the
  /// process.
  @concurrent
  func prepare(fileURL: URL, fingerprint: Fingerprint) async throws -> ResumableSource {
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

  func prepare(data: Data, fingerprint: Fingerprint) throws -> ResumableSource {
    try createDirectory()
    try data.write(to: sandboxCopyURL(fingerprint: fingerprint), options: .atomic)
    return .sandboxCopy
  }

  func fileURL(for record: ResumableUploadRecord) -> URL {
    fileURL(for: record.source, fingerprint: record.fingerprint)
  }

  func fileURL(for source: ResumableSource, fingerprint: Fingerprint) -> URL {
    switch source {
    case .container(let relativePath):
      container.appendingPathComponent(relativePath)
    case .sandboxCopy:
      sandboxCopyURL(fingerprint: fingerprint)
    }
  }

  /// The size and modification date of the file at `url`, as the record keeps them.
  static func attributes(of url: URL) throws -> (size: Int64, modificationDate: Date) {
    let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
    return (
      (attributes[.size] as? NSNumber)?.int64Value ?? 0,
      (attributes[.modificationDate] as? Date) ?? Date(timeIntervalSince1970: 0)
    )
  }

  func save(_ record: ResumableUploadRecord) throws {
    try createDirectory()
    try Self.encoder.encode(record).write(
      to: recordURL(fingerprint: record.fingerprint), options: .atomic)
  }

  /// The record, or `nil` when there is none, it is stale, or it does not decode. A stale or
  /// corrupt record is removed with its sandbox copy. Only files named by a ``Fingerprint`` are
  /// touched, since ``directory`` can be a folder the app shares, such as an app group
  /// container.
  ///
  /// - Throws: The file system's error when the record exists but cannot be read, for example
  ///   while data protection locks it. The record is kept.
  func record(fingerprint: Fingerprint) throws -> ResumableUploadRecord? {
    let url = recordURL(fingerprint: fingerprint)
    let data: Data
    do {
      data = try Data(contentsOf: url)
    } catch CocoaError.fileReadNoSuchFile {
      return nil
    }
    guard let record = try? Self.decoder.decode(ResumableUploadRecord.self, from: data) else {
      removeFiles(fingerprint: fingerprint)
      return nil
    }
    guard !isStale(record) else {
      remove(record)
      return nil
    }
    return record
  }

  /// Every live record, oldest first. Stale and corrupt ones are removed on the way (see
  /// ``record(fingerprint:)``); one that cannot be read is skipped and kept. Files whose name
  /// does not parse as a ``Fingerprint`` are not the store's, and are ignored.
  ///
  /// - Throws: ``StorageError`` when the directory cannot be read.
  func records() throws -> [ResumableUploadRecord] {
    guard FileManager.default.fileExists(atPath: directory.path) else { return [] }
    let names: [String]
    do {
      names = try FileManager.default.contentsOfDirectory(atPath: directory.path)
    } catch {
      throw StorageError(
        kind: .invalidRequest,
        message: "The resumable upload records could not be read.",
        underlyingError: error)
    }
    return
      names
      .compactMap(Fingerprint.init(recordFileName:))
      .compactMap { try? record(fingerprint: $0) }
      .sorted { $0.createdAt < $1.createdAt }
  }

  func remove(_ record: ResumableUploadRecord) {
    try? FileManager.default.removeItem(at: recordURL(fingerprint: record.fingerprint))
    if record.source == .sandboxCopy {
      try? FileManager.default.removeItem(at: sandboxCopyURL(fingerprint: record.fingerprint))
    }
  }

  /// Deletes the record file and the sandbox copy, if any, for `fingerprint`.
  func removeFiles(fingerprint: Fingerprint) {
    try? FileManager.default.removeItem(at: recordURL(fingerprint: fingerprint))
    try? FileManager.default.removeItem(at: sandboxCopyURL(fingerprint: fingerprint))
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

  func recordURL(fingerprint: Fingerprint) -> URL {
    directory.appendingPathComponent("\(fingerprint.rawValue).json")
  }

  private func sandboxCopyURL(fingerprint: Fingerprint) -> URL {
    directory.appendingPathComponent("\(fingerprint.rawValue).bin")
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
