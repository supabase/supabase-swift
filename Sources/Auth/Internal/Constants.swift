//
//  Constants.swift
//
//
//  Created by Guilherme Souza on 22/05/24.
//

import Foundation
import HTTPTypes

let defaultAuthURL = URL(string: "http://localhost:9999")!
let defaultExpiryMargin: Duration = .seconds(30)

let defaultStorageKey = "supabase.auth.token"

extension HTTPField.Name {
  static let apiVersionHeaderName = HTTPField.Name("X-Supabase-Api-Version")!
}
