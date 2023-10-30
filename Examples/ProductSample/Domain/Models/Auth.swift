//
//  Auth.swift
//  ProductSample
//
//  Created by Guilherme Souza on 21/10/23.
//

import Foundation

struct Credentials {
  let email, password: String
}

enum AuthenticationState {
  case signedIn
  case signedOut
}
