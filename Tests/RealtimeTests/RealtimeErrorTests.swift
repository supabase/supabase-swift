//
//  RealtimeErrorTests.swift
//  Supabase
//
//  Created by Guilherme Souza on 29/07/25.
//

import XCTest

@testable import Realtime

final class RealtimeErrorTests: XCTestCase {
  func testRealtimeErrorInitialization() {
    let errorMessage = "Connection failed"
    let error = RealtimeError(errorMessage)
    
    XCTAssertEqual(error.errorDescription, errorMessage)
  }
  
  func testRealtimeErrorLocalizedDescription() {
    let errorMessage = "Test error message"
    let error = RealtimeError(errorMessage)
    
    // LocalizedError protocol provides localizedDescription
    XCTAssertEqual(error.localizedDescription, errorMessage)
  }
  
  func testRealtimeErrorWithEmptyMessage() {
    let error = RealtimeError("")
    XCTAssertEqual(error.errorDescription, "")
  }
  
  func testRealtimeErrorAsError() {
    let errorMessage = "Network timeout"
    let realtimeError = RealtimeError(errorMessage)
    let error: Error = realtimeError
    
    // Test that it can be used as a general Error
    XCTAssertNotNil(error)
    XCTAssertEqual(error.localizedDescription, errorMessage)
  }
  
  func testRealtimeErrorEquality() {
    let error1 = RealtimeError("Same message")
    let error2 = RealtimeError("Same message")
    let error3 = RealtimeError("Different message")
    
    // Since RealtimeError doesn't implement Equatable, we test the description
    XCTAssertEqual(error1.errorDescription, error2.errorDescription)
    XCTAssertNotEqual(error1.errorDescription, error3.errorDescription)
  }
}