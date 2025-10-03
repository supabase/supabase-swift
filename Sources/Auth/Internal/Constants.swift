//
//  Constants.swift
//
//
//  Created by Guilherme Souza on 22/05/24.
//

import Foundation

let defaultAuthURL = URL(string: "http://localhost:9999")!
let defaultExpiryMargin: TimeInterval = 30

let autoRefreshTickDuration: TimeInterval = 30
let autoRefreshTickThreshold = 3

let defaultStorageKey = "supabase.auth.token"
let apiVersionHeaderNameHeaderKey = "X-Supabase-Api-Version"

let apiVersions: [APIVersion.Name: APIVersion] = [
  ._20240101: ._20240101
]

struct APIVersion {
  let timestamp: Date
  let name: Name

  enum Name: String {
    case _20240101 = "2024-01-01"
  }

  static func date(for name: Name) -> Date {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter.date(from: "\(name.rawValue)T00:00:00.0Z")!
  }
}

extension APIVersion {
  static let _20240101 = APIVersion(
    timestamp: APIVersion.date(for: ._20240101),
    name: ._20240101
  )
}
