//
//  MockAPIClient.swift
//
//
//  Created by Guilherme Souza on 25/03/24.
//

import _Helpers
@testable import Auth
import Foundation
import XCTestDynamicOverlay

extension APIClient {
  static let mock = APIClient(execute: unimplemented("APIClient.execute"))
}
