//
//  SupabaseLogHandler.swift
//
//
//  Created by Guilherme Souza on 15/01/24.
//

import ConcurrencyExtras
import Foundation

protocol SupabaseLogHandler: Sendable {
  func didLog(_ entry: SupabaseLogger.Entry)
}

final class DefaultSupabaseLogHandler: SupabaseLogHandler {
  private static let cachedInstances = LockIsolated([URL: DefaultSupabaseLogHandler]())
  static func instance(for url: URL) -> DefaultSupabaseLogHandler {
    if let instance = cachedInstances[url] {
      return instance
    }

    let instance = cachedInstances.withValue {
      let instance = try! DefaultSupabaseLogHandler(localFile: url)
      $0[url] = instance
      return instance
    }

    return instance
  }

  let fileHandle: FileHandle

  private init(localFile url: URL) throws {
    if !FileManager.default.fileExists(atPath: url.path) {
      FileManager.default.createFile(atPath: url.path, contents: nil)
    }

    fileHandle = try FileHandle(forWritingTo: url)
    fileHandle.seekToEndOfFile()
  }

  func didLog(_ entry: SupabaseLogger.Entry) {
    let logLine = "\(entry.description)\n"
    guard let data = logLine.data(using: .utf8) else { return }
    fileHandle.write(data)

    #if DEBUG
      print(entry.description)
    #endif
  }
}
