//
//  main.swift
//  SupabaseTypegen
//
//  Created by Guilherme Souza on 08/10/26.
//

import Foundation

let result = run(arguments: Array(CommandLine.arguments.dropFirst())) {
  FileHandle.standardInput.readDataToEndOfFile()
}
FileHandle.standardOutput.write(Data(result.standardOutput.utf8))
FileHandle.standardError.write(Data(result.standardError.utf8))
exit(result.exitCode)
