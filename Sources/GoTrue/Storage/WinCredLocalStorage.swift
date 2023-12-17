#if os(Windows)
import Foundation
import WinSDK

enum WinCredLocalStorageError: Error {
  case windows(UInt32)
  case other(Int)
}

public struct WinCredLocalStorage: GoTrueLocalStorage {
  private let service: String

  private let credentialType: DWORD
  private let credentialPersistence: DWORD

  public init(service: String) {
    self.service = service
    credentialType = DWORD(CRED_TYPE_GENERIC)
    credentialPersistence = DWORD(CRED_PERSIST_LOCAL_MACHINE)
  }

  public func store(key: String, value: Data) throws {
    var valueData = value

    var credential: CREDENTIALW = .init()

    credential.Type = credentialType
    credential.Persist = credentialPersistence
    "\(service)\\\(key)".withCString(encodedAs: UTF16.self, { keyName in
      credential.TargetName = UnsafeMutablePointer(mutating: keyName)
    })

    withUnsafeMutableBytes(of: &valueData, { data in
      credential.CredentialBlobSize = DWORD(data.count)
      credential.CredentialBlob = data.baseAddress!.assumingMemoryBound(to: UInt8.self)
    })

    if !CredWriteW(&credential, 0) {
      let lastError = GetLastError()
      debugPrint("Unable to save password to credential vault, got error code \(lastError)")

      throw WinCredLocalStorageError.windows(lastError)
    }
  }

  public func retrieve(key: String) throws -> Data? {
    var credential: PCREDENTIALW?

    let targetName = "\(service)\\\(key))".withCString(encodedAs: UTF16.self, { $0 })

    if !CredReadW(targetName, credentialType, 0, &credential) {
      let lastError = GetLastError()
      debugPrint("Unable to find entry for key in credential vault, got error code \(lastError)")

      throw WinCredLocalStorageError.windows(lastError)
    }

    guard let foundCredential = credential, let blob = foundCredential.pointee.CredentialBlob else {
      throw WinCredLocalStorageError.other(-1)
    }

    let blobSize = Int(foundCredential.pointee.CredentialBlobSize)
    let pointer = blob.withMemoryRebound(to: UInt8.self, capacity: blobSize, { $0 })
    let data = Data(bytes: pointer, count: blobSize)

    CredFree(foundCredential)

    return data
  }

  public func remove(key: String) throws {
    let targetName = "\(service)\\\(key))".withCString(encodedAs: UTF16.self, { $0 })

    if !CredDeleteW(targetName, credentialType, 0) {
      let lastError = GetLastError()
      debugPrint("Unable to remove key from credential vault, got error code \(lastError)")

      throw WinCredLocalStorageError.windows(lastError)
    }
  }
}
#endif