//
//  StreamManagerTests.swift
//
//
//  Created by Guilherme Souza on 18/01/24.
//

import Foundation
@testable import Realtime
import XCTest

final class StreamManagerTests: XCTestCase {
  func testYieldInitialValue() async {
    let manager = SharedStream(initialElement: 0)

    let value = await manager.makeStream().first(where: { _ in true })
    XCTAssertEqual(value, 0)
  }
}
