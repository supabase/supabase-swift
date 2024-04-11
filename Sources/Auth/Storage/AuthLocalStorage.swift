import Foundation

public protocol AuthLocalStorage: Sendable {
  func store(key: String, value: Data) throws
  func retrieve(key: String) throws -> Data?
  func remove(key: String) throws
}

extension AuthClient.Configuration {
  public static let defaultLocalStorage: any AuthLocalStorage = KeychainLocalStorage(
    service: "supabase.gotrue.swift",
    accessGroup: nil
  )
}
