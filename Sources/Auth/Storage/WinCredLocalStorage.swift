#if os(Windows)
  import Foundation
  import WinSDK

  enum WinCredLocalStorageError: Error {
    case windows(UInt32)
    case other(Int)
  }

  /// ``AuthLocalStorage`` implementation backed by Windows Credential Manager.
  ///
  /// This is the default local storage on Windows. Items are stored as generic credentials
  /// scoped to the current machine (`CRED_PERSIST_LOCAL_MACHINE`).
  public struct WinCredLocalStorage: AuthLocalStorage {
    private let service: String

    private let credentialType: DWORD
    private let credentialPersistence: DWORD

    /// Creates a Windows Credential Manager–backed storage instance.
    ///
    /// - Parameter service: A namespace string prepended to every credential target name.
    ///   Defaults to `"supabase.gotrue.swift"`.
    public init(service: String = "supabase.gotrue.swift") {
      self.service = service
      credentialType = DWORD(CRED_TYPE_GENERIC)
      credentialPersistence = DWORD(CRED_PERSIST_LOCAL_MACHINE)
    }

    /// Stores `value` in the Windows Credential Manager under `key`.
    ///
    /// - Parameters:
    ///   - key: The credential target name suffix.
    ///   - value: The raw bytes to store.
    /// - Throws: ``WinCredLocalStorageError/windows(_:)`` if `CredWriteW` fails.
    public func store(key: String, value: Data) throws {
      var valueData = value

      var credential: CREDENTIALW = .init()

      credential.Type = credentialType
      credential.Persist = credentialPersistence
      "\(service)\\\(key)".withCString(encodedAs: UTF16.self) { keyName in
        credential.TargetName = UnsafeMutablePointer(mutating: keyName)
      }

      withUnsafeMutableBytes(of: &valueData) { data in
        credential.CredentialBlobSize = DWORD(data.count)
        credential.CredentialBlob = data.baseAddress!.assumingMemoryBound(to: UInt8.self)
      }

      if !CredWriteW(&credential, 0) {
        let lastError = GetLastError()
        debugPrint("Unable to save password to credential vault, got error code \(lastError)")

        throw WinCredLocalStorageError.windows(lastError)
      }
    }

    /// Returns the credential stored under `key`, or `nil` if not present.
    ///
    /// - Parameter key: The credential target name suffix.
    /// - Returns: The stored bytes, or `nil` if the credential does not exist.
    /// - Throws: ``WinCredLocalStorageError/windows(_:)`` if `CredReadW` fails.
    public func retrieve(key: String) throws -> Data? {
      var credential: PCREDENTIALW?

      let targetName = "\(service)\\\(key))".withCString(encodedAs: UTF16.self) { $0 }

      if !CredReadW(targetName, credentialType, 0, &credential) {
        let lastError = GetLastError()
        debugPrint("Unable to find entry for key in credential vault, got error code \(lastError)")

        throw WinCredLocalStorageError.windows(lastError)
      }

      guard let foundCredential = credential,
        let blob = foundCredential.pointee.CredentialBlob
      else {
        throw WinCredLocalStorageError.other(-1)
      }

      let blobSize = Int(foundCredential.pointee.CredentialBlobSize)
      let pointer = blob.withMemoryRebound(to: UInt8.self, capacity: blobSize) { $0 }
      let data = Data(bytes: pointer, count: blobSize)

      CredFree(foundCredential)

      return data
    }

    /// Removes the credential stored under `key`.
    ///
    /// - Parameter key: The credential target name suffix.
    /// - Throws: ``WinCredLocalStorageError/windows(_:)`` if `CredDeleteW` fails.
    public func remove(key: String) throws {
      let targetName = "\(service)\\\(key))".withCString(encodedAs: UTF16.self) { $0 }

      if !CredDeleteW(targetName, credentialType, 0) {
        let lastError = GetLastError()
        debugPrint("Unable to remove key from credential vault, got error code \(lastError)")

        throw WinCredLocalStorageError.windows(lastError)
      }
    }
  }
#endif
