//
//  Constants.swift
//
//
//  Created by Guilherme Souza on 22/05/24.
//

import Foundation
import HTTPTypes

let defaultExpiryMargin: Duration = .seconds(30)

extension HTTPField.Name {
  static let apiVersionHeaderName = HTTPField.Name("X-Supabase-Api-Version")!
}
