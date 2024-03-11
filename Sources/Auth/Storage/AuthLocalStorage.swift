import Foundation

public protocol AuthLocalStorage: Sendable {
  func store(key: String, value: Data) throws
  func retrieve(key: String) throws -> Data?
  func remove(key: String) throws
}

extension AuthClient.Configuration {
  #if !os(Linux) && !os(Windows)
    public static let defaultLocalStorage: some AuthLocalStorage = KeychainLocalStorage(
      service: "supabase.gotrue.swift",
      accessGroup: nil
    )
  #elseif os(Windows)
    public static let defaultLocalStorage: some AuthLocalStorage =
      WinCredLocalStorage(service: "supabase.gotrue.swift")
  #endif
}
