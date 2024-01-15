//
//  Entry.swift
//
//
//  Created by Guilherme Souza on 15/01/24.
//

import Foundation

extension SupabaseLogger {
  public struct Entry: Codable, CustomStringConvertible {
    public let system: String
    public let level: Level
    public let message: String
    public let fileID: String
    public let function: String
    public let line: UInt
    public let timestamp: TimeInterval

    public var description: String {
      let date = iso8601Formatter.string(from: Date(timeIntervalSince1970: timestamp))
      let file = fileID.split(separator: ".", maxSplits: 1).first.map(String.init) ?? fileID
      return "\(date) [\(level)] [\(system)] [\(file).\(function):\(line)] \(message)"
    }
  }
}

private let iso8601Formatter: ISO8601DateFormatter = {
  let formatter = ISO8601DateFormatter()
  formatter.formatOptions = [.withInternetDateTime]
  return formatter
}()
