//
//  RefGenerator.swift
//  RealtimeV3
//
//  Created by Guilherme Souza on 27/06/26.
//

import ConcurrencyExtras

/// A thread-safe monotonic counter that produces string-valued refs for push/reply
/// correlation (Phoenix protocol "ref" field).
struct RefGenerator: Sendable {
  private let counter = LockIsolated(0)

  /// Returns the next ref, starting at "1" and incrementing by 1.
  func next() -> String {
    counter.withValue {
      $0 += 1
      return $0.description
    }
  }
}
