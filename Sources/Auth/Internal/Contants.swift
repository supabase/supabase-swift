//
//  Contants.swift
//
//
//  Created by Guilherme Souza on 22/05/24.
//

import Foundation

let EXPIRY_MARGIN: TimeInterval = 30
let STORAGE_KEY = "supabase.auth.token"

let API_VERSION_HEADER_NAME = "X-Supabase-Api-Version"
let API_VERSIONS: [APIVersion.Name: APIVersion] = [
  ._20240101: ._20240101,
]

struct APIVersion {
  let timestamp: Date
  let name: Name

  enum Name: String {
    case _20240101 = "2024-01-01"
  }
}

extension APIVersion {
  static let _20240101 = APIVersion(
    timestamp: ISO8601DateFormatter().date(from: "\(Name._20240101)T00:00:00.0Z")!,
    name: ._20240101
  )
}
