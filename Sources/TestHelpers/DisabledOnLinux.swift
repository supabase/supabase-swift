//
//  DisabledOnLinux.swift
//  TestHelpers
//
//  Created by Guilherme Souza on 19/10/26.
//

public import Testing

extension Trait where Self == ConditionTrait {
  /// Skips a test or suite on Linux, with the reason it cannot run there yet.
  ///
  /// Prefer this over an `#if os(Linux)` block: the test still compiles on Linux, and the
  /// reason shows up in the test report instead of in a comment.
  package static func disabledOnLinux(_ comment: Comment) -> Self {
    #if os(Linux)
      .disabled(comment)
    #else
      .enabled(if: true)
    #endif
  }
}
