//
//  TransferProgress.swift
//  HTTPRuntime
//
//  Created by Guilherme Souza on 08/07/26.
//
/// Progress of an upload or download.
package struct TransferProgress: Sendable, Hashable {
  /// Bytes transferred so far.
  package let completed: Int64
  /// Total expected bytes, or `nil` when the length is unknown.
  package let total: Int64?

  package init(completed: Int64, total: Int64?) {
    self.completed = completed
    self.total = total
  }

  /// Fraction in `0...1`, or `nil` when the total is unknown.
  package var fraction: Double? {
    guard let total, total > 0 else { return nil }
    return Double(completed) / Double(total)
  }
}

/// A `@Sendable` progress callback invoked as bytes move.
package typealias ProgressHandler = @Sendable (TransferProgress) -> Void
