import Foundation

public enum LocalStorageEngines {
  public static func platformSpecific() -> some GoTrueLocalStorage {
    #if os(iOS) || os(macOS) || os(watchOS)
    KeychainLocalStorage(service: "supabase.gotrue.swift", accessGroup: nil)
    #elseif os(Windows)
    WinCredLocalStorage(service: "supabase.gotrue.swift")
    #else
    preconditionFailure("There is no default storage engine implemented for this platform, please set your own implementation.")
    #endif
  }
}