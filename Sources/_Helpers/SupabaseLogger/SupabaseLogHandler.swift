//
//  SupabaseLogHandler.swift
//
//
//  Created by Guilherme Souza on 15/01/24.
//

import Foundation

public protocol SupabaseLogHandler: Sendable {
  func didLog(_ entry: SupabaseLogger.Entry)
}

public final class DefaultSupabaseLogHandler: SupabaseLogHandler {
  /// The default log handler instance used across all Supabase sub-packages.
  public static let shared: SupabaseLogHandler = try! DefaultSupabaseLogHandler(
    localFile: FileManager.default.url(
      for: .applicationSupportDirectory,
      in: .userDomainMask,
      appropriateFor: nil,
      create: true
    ).appendingPathComponent("supabase-swift.log")
  )

  let fileHandle: FileHandle

  public init(localFile url: URL) throws {
    if !FileManager.default.fileExists(atPath: url.path) {
      FileManager.default.createFile(atPath: url.path, contents: nil)
    }

    fileHandle = try FileHandle(forWritingTo: url)
    fileHandle.seekToEndOfFile()

    debugPrint("SupabaseLogHandler initialized at: \(url)")
  }

  public func didLog(_ entry: SupabaseLogger.Entry) {
    let logLine = "\(entry.description)\n"
    guard let data = logLine.data(using: .utf8) else { return }
    fileHandle.write(data)

    debugPrint(entry.description)
  }
}

@_spi(Internal)
public struct NoopSupabaseLogHandler: SupabaseLogHandler {
  public init() {}
  public func didLog(_: SupabaseLogger.Entry) {}
}
