//
//  Logger.swift
//
//
//  Created by Guilherme Souza on 11/12/23.
//

import Foundation

private let _debugLoggingEnabled = LockedState(initialState: false)
var debugLoggingEnabled: Bool {
  get { _debugLoggingEnabled.withLock { $0 } }
  set { _debugLoggingEnabled.withLock { $0 = newValue } }
}

private let standardError = LockedState(initialState: FileHandle.standardError)
func debug(
  _ message: @autoclosure () -> String,
  function: String = #function,
  file: String = #file,
  line: UInt = #line
) {
  assert(
    {
      if debugLoggingEnabled {
        standardError.withLock {
          let logLine = "[\(function) \(file.split(separator: "/").last!):\(line)] \(message())\n"
          $0.write(Data(logLine.utf8))
        }
      }

      return true
    }()
  )
}
