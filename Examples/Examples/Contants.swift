//
//  Contants.swift
//  Examples
//
//  Created by Guilherme Souza on 15/12/23.
//

import Foundation

enum Constants {
  static let redirectToURL = URL(string: "com.supabase.swift-examples://")!
}

extension URL {
  init?(scheme: String) {
    var components = URLComponents()
    components.scheme = scheme

    guard let url = components.url else {
      return nil
    }

    self = url
  }
}
