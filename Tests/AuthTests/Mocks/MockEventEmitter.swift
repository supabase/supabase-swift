//
//  MockEventEmitter.swift
//
//
//  Created by Guilherme Souza on 15/02/24.
//

@testable import Auth
import ConcurrencyExtras
import Foundation
import XCTestDynamicOverlay

extension EventEmitter {
  static let mock = EventEmitter(
    attachListener: unimplemented("EventEmitter.attachListener"),
    emit: unimplemented("EventEmitter.emit")
  )
}
