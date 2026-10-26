import Crypto
public import Foundation

#if canImport(Darwin)
  import Darwin
#elseif canImport(Glibc)
  import Glibc
#elseif canImport(Musl)
  import Musl
#elseif canImport(Android)
  import Android
#endif

/// An ``AuthStorage`` that stores each value in its own file in a directory.
///
/// Use it on platforms without a Keychain, such as Linux and Android. Each file is readable and
/// writable by its owner only (POSIX permissions `0600`). The contents are not encrypted, so
/// pick a directory that only the app can reach. On Android, prefer a custom ``AuthStorage``
/// backed by the Android Keystore.
///
/// Each key maps to a file named after the SHA-256 hash of the key. Any key, including one
/// with `/` or `..` in it, stays inside the directory.
///
/// A write goes to a new temporary file that is then renamed over the old one. A reader sees
/// either the old value or the new one, never a partial file. This holds across instances and
/// processes that share the directory. When writes to the same key race, the last rename wins.
///
/// On Windows, POSIX permissions do not apply; the file inherits the directory's access control.
public struct FileAuthStorage: AuthStorage {
  let directory: URL

  /// Creates a storage that keeps its files in `directory`.
  ///
  /// - Parameter directory: The directory for the files. It is created with permissions `0700`
  ///   on the first write if it does not exist.
  public init(directory: URL) {
    self.directory = directory
  }

  /// Returns the bytes stored under `key`, or `nil` when no file exists for it.
  ///
  /// - Throws: The file system error when the file exists but cannot be read.
  @concurrent
  public func load(key: String) async throws -> Data? {
    do {
      return try Data(contentsOf: fileURL(forKey: key))
    } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
      return nil
    }
  }

  /// Stores `data` under `key`, replacing any value already stored under it.
  ///
  /// - Throws: The file system error when the directory cannot be created or the file cannot
  ///   be written.
  @concurrent
  public func save(_ data: Data, key: String) async throws {
    try FileManager.default.createDirectory(
      at: directory,
      withIntermediateDirectories: true,
      attributes: [.posixPermissions: 0o700]
    )
    try Self.writeAtomically(data, to: fileURL(forKey: key))
  }

  /// Removes the file stored under `key`. Removing a key with no file succeeds.
  ///
  /// - Throws: The file system error when the file exists but cannot be deleted.
  @concurrent
  public func remove(key: String) async throws {
    do {
      try FileManager.default.removeItem(at: fileURL(forKey: key))
    } catch let error as CocoaError where error.code == .fileNoSuchFile {
    }
  }

  func fileURL(forKey key: String) -> URL {
    let name = SHA256.hash(data: Data(key.utf8)).map { String(format: "%02x", $0) }.joined()
    return directory.appendingPathComponent(name, isDirectory: false)
  }

  #if os(Windows)
    static func writeAtomically(_ data: Data, to url: URL) throws {
      try data.write(to: url, options: .atomic)
    }
  #else
    // `Data.write(to:options: .atomic)` gives a new file the umask's permissions (often 0644),
    // so the token would be readable by others until a later chmod. Creating the temporary
    // file with 0600 closes that window.
    static func writeAtomically(_ data: Data, to url: URL) throws {
      let temporaryPath = url.deletingLastPathComponent()
        .appendingPathComponent(".\(UUID().uuidString).tmp", isDirectory: false).path
      let descriptor = open(temporaryPath, O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC, 0o600)
      guard descriptor >= 0 else { throw POSIXError.fromErrno() }

      do {
        try writeAll(data, to: descriptor)
        guard fsync(descriptor) == 0 else { throw POSIXError.fromErrno() }
      } catch {
        close(descriptor)
        unlink(temporaryPath)
        throw error
      }

      guard close(descriptor) == 0, rename(temporaryPath, url.path) == 0 else {
        let error = POSIXError.fromErrno()
        unlink(temporaryPath)
        throw error
      }
    }

    private static func writeAll(_ data: Data, to descriptor: Int32) throws {
      try data.withUnsafeBytes { buffer in
        guard var pointer = buffer.baseAddress else { return }
        var remaining = buffer.count
        while remaining > 0 {
          let written = write(descriptor, pointer, remaining)
          if written < 0 {
            if errno == EINTR { continue }
            throw POSIXError.fromErrno()
          }
          pointer += written
          remaining -= written
        }
      }
    }
  #endif
}

#if !os(Windows)
  extension POSIXError {
    fileprivate static func fromErrno() -> POSIXError {
      POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
    }
  }
#endif
