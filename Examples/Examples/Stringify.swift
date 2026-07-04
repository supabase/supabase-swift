//
//  Stringify.swift
//  Examples
//
//  Created by Guilherme Souza on 21/03/24.
//

import CustomDump
import Foundation

func stringify(_ value: Any) -> String {
  var output = ""
  customDump(value, to: &output)
  return output
}
