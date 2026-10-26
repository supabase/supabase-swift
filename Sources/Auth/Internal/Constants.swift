//
//  Constants.swift
//
//
//  Created by Guilherme Souza on 22/05/24.
//

import Foundation
import HTTPTypes

let defaultAuthURL = URL(string: "http://localhost:9999")!
let defaultExpiryMargin: TimeInterval = 30

let autoRefreshTickDuration: TimeInterval = 30
let autoRefreshTickThreshold = 3

let defaultStorageKey = "supabase.auth.token"

extension HTTPField.Name {
  static let apiVersionHeaderName = HTTPField.Name("X-Supabase-Api-Version")!
}
