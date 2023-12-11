//
//  Logger.swift
//
//
//  Created by Guilherme Souza on 11/12/23.
//

import ConcurrencyExtras
import Foundation

private let _debugLoggingEnabled = LockIsolated(false)
@_spi(Internal) public var debugLoggingEnabled: Bool {
  get { _debugLoggingEnabled.value }
  set { _debugLoggingEnabled.setValue(newValue) }
}

private let standardError = LockIsolated(FileHandle.standardError)
@_spi(Internal) public func debug(
  _ message: @autoclosure () -> String,
  function: String = #function,
  file: String = #file,
  line: UInt = #line
) {
  assert(
    {
      if debugLoggingEnabled {
        standardError.withValue {
          let logLine = "[\(function) \(file.split(separator: "/").last!):\(line)] \(message())\n"
          $0.write(Data(logLine.utf8))
        }
      }

      return true
    }()
  )
}
