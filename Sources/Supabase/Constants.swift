//
//  Constants.swift
//  Supabase
//
//  Created by Guilherme Souza on 06/03/25.
//

import Foundation
import Helpers

let defaultHeaders: [String: String] = {
  var headers = [
    "X-Client-Info": "supabase-swift/\(version)"
  ]

  if let platform {
    headers["X-Supabase-Client-Platform"] = platform
  }

  if let platformVersion {
    headers["X-Supabase-Client-Platform-Version"] = platformVersion
  }

  return headers
}()
