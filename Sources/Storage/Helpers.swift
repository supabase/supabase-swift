//
//  Helpers.swift
//
//
//  Created by Guilherme Souza on 22/05/24.
//

import Foundation

extension String {
  var pathExtension: String {
    (self as NSString).pathExtension
  }

  var fileName: String {
    (self as NSString).lastPathComponent
  }
}
