//
//  WithMainSerialExecutor+Unsupported.swift
//
//
//  Created by Guilherme Souza on 12/03/24.
//

import Foundation

// ConcurrencyExtras only vends `withMainSerialExecutor` where it can swap the Swift runtime's
// global executor hook, which excludes Windows and Android. These overloads keep the call sites
// compiling there; the tests still run, just without the serialized scheduling that makes the
// order they interleave in deterministic.
#if os(Windows) || os(Android)
  /// Calling this method on Windows and Android has no effect.
  @MainActor
  public func withMainSerialExecutor(
    @_implicitSelfCapture operation: @Sendable () async throws -> Void
  ) async rethrows {
    try await operation()
  }

  /// Calling this method on Windows and Android has no effect.
  public func withMainSerialExecutor(
    @_implicitSelfCapture operation: () throws -> Void
  ) rethrows {
    try operation()
  }
#endif
