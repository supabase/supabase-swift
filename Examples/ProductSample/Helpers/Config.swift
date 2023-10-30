//
//  Config.swift
//  ProductSample
//
//  Created by Guilherme Souza on 19/10/23.
//

import Foundation

enum Config {
  static let SUPABASE_URL = load(key: "SUPABASE_URL") ?? ""
  static let SUPABASE_ANON_KEY = load(key: "SUPABASE_ANON_KEY") ?? ""

  private static func load<T>(key: String) -> T? {
    guard
      let configURL = Bundle.main.url(forResource: "Config", withExtension: "plist"),
      let config = try? PropertyListSerialization.propertyList(
        from: Data(contentsOf: configURL), format: nil
      ) as? [String: Any]
    else {
      return nil
    }

    return config[key] as? T
  }
}
