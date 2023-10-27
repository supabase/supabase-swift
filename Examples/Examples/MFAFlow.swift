//
//  MFAFlow.swift
//  Examples
//
//  Created by Guilherme Souza on 27/10/23.
//

import SwiftUI

enum MFAStatus {
  case unenrolled
  case unverified
  case verified
  case disabled

  var description: String {
    switch self {
    case .unenrolled:
      "User does not have MFA enrolled."
    case .unverified:
      "User has an MFA factor enrolled but has not verified it."
    case .verified:
      "User has verified their MFA factor."
    case .disabled:
      "User has disabled their MFA factor. (Stale JWT.)"
    }
  }
}

struct MFAFlow: View {
  let status: MFAStatus

  var body: some View {
    Text(status.description)
  }
}
