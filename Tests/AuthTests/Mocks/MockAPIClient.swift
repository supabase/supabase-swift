//
//  MockAPIClient.swift
//
//
//  Created by Guilherme Souza on 25/03/24.
//

@testable import Auth
import Foundation
@_spi(Internal) import _Helpers
import XCTestDynamicOverlay

extension APIClient {
  static let mock = APIClient(execute: unimplemented("APIClient.execute"))
}
