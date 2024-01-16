import Foundation

public protocol AuthLocalStorage: Sendable {
  func store(key: String, value: Data) throws
  func retrieve(key: String) throws -> Data?
  func remove(key: String) throws
}

extension AuthClient.Configuration {
  #if os(iOS) || os(macOS) || os(watchOS) || os(tvOS)
    public static let defaultAuthLocalStorage = KeychainLocalStorage(
      service: "supabase.gotrue.swift",
      accessGroup: nil
    )
  #elseif os(Windows)
    public static let defaultAuthLocalStorage =
      WinCredLocalStorage(service: "supabase.gotrue.swift")
  #endif
}
