//
//  ServerSentEvents.swift
//  HTTPRuntime
//
//  Created by Guilherme Souza on 08/07/26.
//
import Foundation

/// A single Server-Sent Event frame (`text/event-stream`).
public struct ServerSentEvent: Sendable, Hashable {
  public var event: String?
  public var data: String
  public var id: String?
  public var retry: Int?

  public init(event: String? = nil, data: String, id: String? = nil, retry: Int? = nil) {
    self.event = event
    self.data = data
    self.id = id
    self.retry = retry
  }
}

extension AsyncThrowingStream where Element == Data, Failure == any Error {
  /// Parses this stream of raw byte chunks into SSE frames, splitting on the
  /// blank-line frame delimiter and coalescing multi-line `data:` fields per
  /// the SSE spec. Generated code maps each frame's `data` (JSON) into the
  /// operation's typed event union.
  public func serverSentEvents() -> AsyncThrowingStream<ServerSentEvent, any Error> {
    AsyncThrowingStream<ServerSentEvent, any Error> { continuation in
      let task = Task {
        var buffer = Data()
        do {
          for try await chunk in self {
            buffer.append(chunk)
            while let frame = Self.extractFrame(&buffer) {
              if let event = Self.parseFrame(frame) {
                continuation.yield(event)
              }
            }
          }
          // Flush any trailing frame without a terminating blank line.
          if !buffer.isEmpty, let event = Self.parseFrame(buffer) {
            continuation.yield(event)
          }
          continuation.finish()
        } catch {
          continuation.finish(throwing: error)
        }
      }
      continuation.onTermination = { _ in task.cancel() }
    }
  }

  /// Pulls one complete frame (bytes up to and including `\n\n`) out of the
  /// buffer, or returns nil if no full frame is buffered yet.
  private static func extractFrame(_ buffer: inout Data) -> Data? {
    let delimiter = Data([0x0A, 0x0A])  // "\n\n"
    guard let range = buffer.range(of: delimiter) else { return nil }
    let frame = buffer.subdata(in: buffer.startIndex..<range.lowerBound)
    buffer.removeSubrange(buffer.startIndex..<range.upperBound)
    return frame
  }

  private static func parseFrame(_ frame: Data) -> ServerSentEvent? {
    guard let text = String(data: frame, encoding: .utf8) else { return nil }
    var event: String?
    var id: String?
    var retry: Int?
    var dataLines: [String] = []
    for rawLine in text.split(separator: "\n", omittingEmptySubsequences: false) {
      let line = rawLine.hasSuffix("\r") ? String(rawLine.dropLast()) : String(rawLine)
      if line.isEmpty || line.hasPrefix(":") { continue }  // comment / blank
      let field: Substring
      let value: String
      if let colon = line.firstIndex(of: ":") {
        field = line[line.startIndex..<colon]
        var v = line[line.index(after: colon)...]
        if v.first == " " { v = v.dropFirst() }
        value = String(v)
      } else {
        field = Substring(line)
        value = ""
      }
      switch field {
      case "event": event = value
      case "data": dataLines.append(value)
      case "id": id = value
      case "retry": retry = Int(value)
      default: break
      }
    }
    guard !dataLines.isEmpty || event != nil else { return nil }
    return ServerSentEvent(
      event: event, data: dataLines.joined(separator: "\n"), id: id, retry: retry)
  }
}
