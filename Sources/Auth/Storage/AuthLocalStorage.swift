import Foundation

public protocol AuthLocalStorage: Sendable {
  func store(key: String, value: Data) throws
  func retrieve(key: String) throws -> Data?
  func remove(key: String) throws
}

extension AuthClient.Configuration {
  public static let defaultLocalStorage: AuthLocalStorage = {
    #if os(iOS) || os(macOS) || os(watchOS) || os(tvOS)
      KeychainLocalStorage(
        service: "supabase.gotrue.swift",
        accessGroup: nil
      )
    #elseif os(Windows)
      WinCredLocalStorage(service: "supabase.gotrue.swift")
    #endif
  }()
}
