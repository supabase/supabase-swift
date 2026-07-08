//
//  TransferProgress.swift
//  HTTPRuntime
//
//  Created by Guilherme Souza on 08/07/26.
//
/// Progress of an upload or download.
public struct TransferProgress: Sendable, Hashable {
  /// Bytes transferred so far.
  public let completed: Int64
  /// Total expected bytes, or `nil` when the length is unknown.
  public let total: Int64?

  public init(completed: Int64, total: Int64?) {
    self.completed = completed
    self.total = total
  }

  /// Fraction in `0...1`, or `nil` when the total is unknown.
  public var fraction: Double? {
    guard let total, total > 0 else { return nil }
    return Double(completed) / Double(total)
  }
}

/// A `@Sendable` progress callback invoked as bytes move.
public typealias ProgressHandler = @Sendable (TransferProgress) -> Void
