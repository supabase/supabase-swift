//
//  KeychainLocalStorageTests.swift
//  Supabase
//
//  Created by Coverage Tests
//

import XCTest
@testable import Auth

#if !os(Windows) && !os(Linux) && !os(Android)
final class KeychainLocalStorageTests: XCTestCase {

  var storage: KeychainLocalStorage!
  let testKey = "test-storage-key-\(UUID().uuidString)"

  override func setUp() {
    super.setUp()
    storage = KeychainLocalStorage(service: "com.supabase.tests.storage", accessGroup: nil)
    // Clean up any existing test data
    try? storage.remove(key: testKey)
  }

  override func tearDown() {
    // Clean up test data
    try? storage.remove(key: testKey)
    super.tearDown()
  }

  // MARK: - Store and Retrieve Tests

  func testStoreAndRetrieveData() throws {
    let testData = "Test session data".data(using: .utf8)!

    // Store data
    try storage.store(key: testKey, value: testData)

    // Retrieve data
    let retrieved = try storage.retrieve(key: testKey)
    XCTAssertEqual(retrieved, testData)
  }

  func testStoreEmptyData() throws {
    let emptyData = Data()

    try storage.store(key: testKey, value: emptyData)
    let retrieved = try storage.retrieve(key: testKey)

    XCTAssertEqual(retrieved, emptyData)
    XCTAssertEqual(retrieved?.count, 0)
  }

  func testStoreLargeData() throws {
    // Store a large session object (simulate a large JWT or session data)
    let largeData = Data(repeating: 0xFF, count: 10_000)

    try storage.store(key: testKey, value: largeData)
    let retrieved = try storage.retrieve(key: testKey)

    XCTAssertEqual(retrieved, largeData)
    XCTAssertEqual(retrieved?.count, 10_000)
  }

  func testUpdateExistingData() throws {
    let initialData = "Initial session".data(using: .utf8)!
    let updatedData = "Updated session".data(using: .utf8)!

    // Store initial data
    try storage.store(key: testKey, value: initialData)

    // Update with new data
    try storage.store(key: testKey, value: updatedData)

    // Verify update
    let retrieved = try storage.retrieve(key: testKey)
    XCTAssertEqual(retrieved, updatedData)
    XCTAssertNotEqual(retrieved, initialData)
  }

  // MARK: - Remove Tests

  func testRemoveData() throws {
    let testData = "Data to remove".data(using: .utf8)!

    // Store data
    try storage.store(key: testKey, value: testData)

    // Remove data
    try storage.remove(key: testKey)

    // Verify removal - should throw or return nil
    XCTAssertThrowsError(try storage.retrieve(key: testKey))
  }

  func testRemoveNonExistentKey() {
    // Removing a non-existent key should throw
    XCTAssertThrowsError(try storage.remove(key: "non-existent-\(UUID())"))
  }

  // MARK: - Retrieve Tests

  func testRetrieveNonExistentKey() {
    // Retrieving non-existent key should throw
    XCTAssertThrowsError(try storage.retrieve(key: "non-existent-\(UUID())"))
  }

  // MARK: - Multiple Keys Tests

  func testStoreMultipleKeys() throws {
    let key1 = "session-1-\(UUID())"
    let key2 = "session-2-\(UUID())"
    let data1 = "Session 1".data(using: .utf8)!
    let data2 = "Session 2".data(using: .utf8)!

    defer {
      try? storage.remove(key: key1)
      try? storage.remove(key: key2)
    }

    // Store multiple keys
    try storage.store(key: key1, value: data1)
    try storage.store(key: key2, value: data2)

    // Retrieve and verify both
    XCTAssertEqual(try storage.retrieve(key: key1), data1)
    XCTAssertEqual(try storage.retrieve(key: key2), data2)

    // Remove one key
    try storage.remove(key: key1)

    // Verify first is removed, second still exists
    XCTAssertThrowsError(try storage.retrieve(key: key1))
    XCTAssertEqual(try storage.retrieve(key: key2), data2)
  }

  // MARK: - Initialization Tests

  func testDefaultInitialization() {
    let defaultStorage = KeychainLocalStorage()
    XCTAssertNotNil(defaultStorage)
  }

  func testInitializationWithCustomService() {
    let customStorage = KeychainLocalStorage(service: "custom.service.test")
    XCTAssertNotNil(customStorage)

    // Test that it works
    let testData = "Test".data(using: .utf8)!
    let testKey = "custom-test-\(UUID())"

    do {
      try customStorage.store(key: testKey, value: testData)
      let retrieved = try customStorage.retrieve(key: testKey)
      XCTAssertEqual(retrieved, testData)
      try customStorage.remove(key: testKey)
    } catch {
      XCTFail("Custom service storage should work: \(error)")
    }
  }

  func testInitializationWithAccessGroup() {
    let groupStorage = KeychainLocalStorage(
      service: "test.service",
      accessGroup: "group.com.supabase.test"
    )
    XCTAssertNotNil(groupStorage)
  }

  // MARK: - JSON Data Tests

  func testStoreAndRetrieveJSONData() throws {
    // Simulate storing a session as JSON
    let sessionJSON = """
      {
        "access_token": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...",
        "refresh_token": "refresh_token_value",
        "expires_in": 3600,
        "user": {
          "id": "123",
          "email": "test@example.com"
        }
      }
      """

    guard let jsonData = sessionJSON.data(using: .utf8) else {
      XCTFail("Failed to create JSON data")
      return
    }

    try storage.store(key: testKey, value: jsonData)
    let retrieved = try storage.retrieve(key: testKey)

    XCTAssertEqual(retrieved, jsonData)

    // Verify it's valid JSON
    XCTAssertNoThrow(try JSONSerialization.jsonObject(with: retrieved!, options: []))
  }

  // MARK: - Special Characters in Keys Tests

  func testStoreWithSpecialCharactersInKey() throws {
    let specialKeys = [
      "key.with.dots",
      "key-with-dashes",
      "key_with_underscores",
      "com.company.app.session",
    ]

    for key in specialKeys {
      let testData = "Data for \(key)".data(using: .utf8)!

      do {
        try storage.store(key: key, value: testData)
        let retrieved = try storage.retrieve(key: key)
        XCTAssertEqual(retrieved, testData, "Failed for key: \(key)")
        try storage.remove(key: key)
      } catch {
        XCTFail("Should handle key '\(key)': \(error)")
      }
    }
  }

  // MARK: - Concurrent Access Tests

  func testConcurrentStoreAndRetrieve() throws {
    let expectation = self.expectation(description: "Concurrent operations")
    expectation.expectedFulfillmentCount = 10

    let queue = DispatchQueue(label: "test.concurrent", attributes: .concurrent)

    for i in 0..<10 {
      queue.async {
        let key = "concurrent-\(i)-\(UUID())"
        let data = "Data \(i)".data(using: .utf8)!

        do {
          try self.storage.store(key: key, value: data)
          let retrieved = try self.storage.retrieve(key: key)
          XCTAssertEqual(retrieved, data)
          try self.storage.remove(key: key)
          expectation.fulfill()
        } catch {
          XCTFail("Concurrent operation failed: \(error)")
        }
      }
    }

    wait(for: [expectation], timeout: 5.0)
  }
}
#endif
