//
//  PostgrestErrorTests.swift
//  Supabase
//
//  Created by Guilherme Souza on 07/05/24.
//

import Foundation
import Helpers
import XCTest

final class PostgrestErrorTests: XCTestCase {

    func testLocalizedErrorConformance() {
        let error = PostgrestError(message: "test error message")
        XCTAssertEqual(error.errorDescription, "test error message")
    }

} 