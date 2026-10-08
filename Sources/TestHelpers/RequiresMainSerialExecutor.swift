//
//  RequiresMainSerialExecutor.swift
//  TestHelpers
//
//  Created by Guilherme Souza on 17/09/26.
//

public import Testing

extension Trait where Self == ConditionTrait {
  /// Skips a test that needs `withMainSerialExecutor` to be more than a passthrough.
  ///
  /// A test that drives a `TestClock` has to know the task it is about to unblock already
  /// reached its `sleep`. `withMainSerialExecutor` guarantees that by pinning every task to
  /// one executor. ConcurrencyExtras cannot implement it on Windows or Android, so
  /// ``withMainSerialExecutor(operation:)`` degrades to running the body unchanged and
  /// `advance(by:)` races the task it was meant to wake — the test then hangs or observes a
  /// half-finished sequence of events.
  public static var requiresMainSerialExecutor: Self {
    #if os(Windows) || os(Android)
      .disabled("withMainSerialExecutor is a no-op on this platform.")
    #else
      .enabled(if: true)
    #endif
  }
}
