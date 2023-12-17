import Foundation

public enum LocalStorageEngines {
  #if os(iOS) || os(macOS) || os(watchOS) || os(tvOS)
  public static let keychain: some GoTrueLocalStorage = {
    KeychainLocalStorage(service: "supabase.gotrue.swift", accessGroup: nil)
  }()
  #endif

  #if os(Windows)
  public static let wincred: some GoTrueLocalStorage = {
    WinCredLocalStorage(service: "supabase.gotrue.swift")
  }()
  #endif
}