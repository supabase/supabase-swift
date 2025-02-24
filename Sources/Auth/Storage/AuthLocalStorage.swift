import Foundation

public protocol AuthLocalStorage: Sendable {
  func store(key: String, value: Data) throws
  func retrieve(key: String) throws -> Data?
  func remove(key: String) throws
}

extension AuthClient.Configuration {
  #if !os(Linux) && !os(Windows) && !os(Android)
    public static let defaultLocalStorage: any AuthLocalStorage = KeychainLocalStorage()
  #elseif os(Windows)
    public static let defaultLocalStorage: any AuthLocalStorage = WinCredLocalStorage()
  #endif
}
