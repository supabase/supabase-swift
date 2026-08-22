//
//  Plugin.swift
//  PostgrestMacrosPlugin
//
//  Created by Guilherme Souza on 21/08/26.
//

import SwiftCompilerPlugin
import SwiftSyntaxMacros

@main
struct PostgrestMacrosPlugin: CompilerPlugin {
  let providingMacros: [any Macro.Type] = [
    MarkerMacro.self,
    TableMacro.self,
  ]
}
