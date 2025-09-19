//
//  Constants.swift
//  Supabase
//
//  Created by Guilherme Souza on 06/03/25.
//

import Alamofire
import Foundation

let defaultHeaders: HTTPHeaders = {
  var headers = HTTPHeaders([
    "X-Client-Info": "supabase-swift/\(version)"
  ])

  if let platform {
    headers["X-Supabase-Client-Platform"] = platform
  }

  if let platformVersion {
    headers["X-Supabase-Client-Platform-Version"] = platformVersion
  }

  return headers
}()
