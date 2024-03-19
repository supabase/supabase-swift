//
//  WithMainSerialExecutor+Windows.swift
//
//
//  Created by Guilherme Souza on 12/03/24.
//

import Foundation

#if os(Windows)
  /// Calling this method on Windows has no effect.
  public func withMainSerialExecutor(
    @_implicitSelfCapture operation: () throws -> Void
  ) rethrows {
    try operation()
  }
#endif
