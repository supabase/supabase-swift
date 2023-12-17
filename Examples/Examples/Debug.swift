//
//  Debug.swift
//  Examples
//
//  Created by Guilherme Souza on 15/12/23.
//

import Foundation

func debug(
  _ message: @autoclosure () -> String,
  function: String = #function,
  file: String = #file,
  line: UInt = #line
) {
  assert(
    {
      let fileHandle = FileHandle.standardError

      let logLine = "[\(function) \(file.split(separator: "/").last!):\(line)] \(message())\n"
      fileHandle.write(Data(logLine.utf8))

      return true
    }()
  )
}
