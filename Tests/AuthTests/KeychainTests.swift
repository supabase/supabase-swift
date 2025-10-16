//
//  KeychainTests.swift
//  Supabase
//
//  Created by Coverage Tests
//

import XCTest
@testable import Auth

#if !os(Windows) && !os(Linux) && !os(Android)
final class KeychainTests: XCTestCase {

  var keychain: Keychain!
  let testService = "com.supabase.tests.keychain"
  let testKey = "test-key-\(UUID().uuidString)"

  override func setUp() {
    super.setUp()
    keychain = Keychain(service: testService, accessGroup: nil)
    // Clean up any existing test data
    try? keychain.deleteItem(forKey: testKey)
  }

  override func tearDown() {
    // Clean up test data
    try? keychain.deleteItem(forKey: testKey)
    super.tearDown()
  }

  // MARK: - Set and Get Tests

  func testSetAndGetData() throws {
    let testData = "Hello, Keychain!".data(using: .utf8)!

    // Set data
    try keychain.set(testData, forKey: testKey)

    // Get data
    let retrievedData = try keychain.data(forKey: testKey)
    XCTAssertEqual(retrievedData, testData)
  }

  func testUpdateExistingData() throws {
    let initialData = "Initial".data(using: .utf8)!
    let updatedData = "Updated".data(using: .utf8)!

    // Set initial data
    try keychain.set(initialData, forKey: testKey)

    // Update with new data
    try keychain.set(updatedData, forKey: testKey)

    // Verify update
    let retrievedData = try keychain.data(forKey: testKey)
    XCTAssertEqual(retrievedData, updatedData)
    XCTAssertNotEqual(retrievedData, initialData)
  }

  func testDeleteData() throws {
    let testData = "To be deleted".data(using: .utf8)!

    // Set data
    try keychain.set(testData, forKey: testKey)

    // Delete data
    try keychain.deleteItem(forKey: testKey)

    // Verify deletion - should throw itemNotFound
    XCTAssertThrowsError(try keychain.data(forKey: testKey)) { error in
      guard let keychainError = error as? KeychainError else {
        XCTFail("Expected KeychainError")
        return
      }
      XCTAssertEqual(keychainError.code, .itemNotFound)
    }
  }

  // MARK: - Error Tests

  func testGetNonExistentKey() {
    XCTAssertThrowsError(try keychain.data(forKey: "non-existent-key-\(UUID())")) { error in
      guard let keychainError = error as? KeychainError else {
        XCTFail("Expected KeychainError")
        return
      }
      XCTAssertEqual(keychainError.code, .itemNotFound)
    }
  }

  func testDeleteNonExistentKey() {
    XCTAssertThrowsError(try keychain.deleteItem(forKey: "non-existent-key-\(UUID())")) { error in
      guard let keychainError = error as? KeychainError else {
        XCTFail("Expected KeychainError")
        return
      }
      XCTAssertEqual(keychainError.code, .itemNotFound)
    }
  }

  // MARK: - KeychainError Tests

  func testKeychainErrorCodes() {
    let errorCodes: [(KeychainError.Code, OSStatus)] = [
      (.operationNotImplemented, errSecUnimplemented),
      (.invalidParameters, errSecParam),
      (.userCanceled, errSecUserCanceled),
      (.itemNotAvailable, errSecNotAvailable),
      (.authFailed, errSecAuthFailed),
      (.duplicateItem, errSecDuplicateItem),
      (.itemNotFound, errSecItemNotFound),
      (.interactionNotAllowed, errSecInteractionNotAllowed),
      (.decodeFailed, errSecDecode),
    ]

    for (code, expectedStatus) in errorCodes {
      XCTAssertEqual(code.rawValue, expectedStatus)
      XCTAssertEqual(KeychainError.Code(rawValue: expectedStatus), code)
    }
  }

  func testKeychainErrorOtherStatus() {
    let customStatus: OSStatus = -99999
    let code = KeychainError.Code(rawValue: customStatus)
    if case let .other(status) = code {
      XCTAssertEqual(status, customStatus)
    } else {
      XCTFail("Expected .other case")
    }
  }

  func testKeychainErrorDescriptions() {
    let errors: [(KeychainError, String)] = [
      (.operationNotImplemented, "errSecUnimplemented"),
      (.invalidParameters, "errSecParam"),
      (.userCanceled, "errSecUserCanceled"),
      (.itemNotAvailable, "errSecNotAvailable"),
      (.authFailed, "errSecAuthFailed"),
      (.duplicateItem, "errSecDuplicateItem"),
      (.itemNotFound, "errSecItemNotFound"),
      (.interactionNotAllowed, "errSecInteractionNotAllowed"),
      (.decodeFailed, "errSecDecode"),
    ]

    for (error, expectedSubstring) in errors {
      XCTAssertTrue(
        error.debugDescription.contains(expectedSubstring),
        "Error description should contain \(expectedSubstring), got: \(error.debugDescription)"
      )
    }
  }

  func testKeychainErrorUnknown() {
    let unknownError = KeychainError(code: .unknown(message: "Test unknown error"))
    XCTAssertTrue(unknownError.debugDescription.contains("Test unknown error"))
    XCTAssertEqual(unknownError.status, errSecSuccess)
  }

  func testKeychainErrorEquality() {
    let error1 = KeychainError.itemNotFound
    let error2 = KeychainError.itemNotFound
    let error3 = KeychainError.duplicateItem

    XCTAssertEqual(error1, error2)
    XCTAssertNotEqual(error1, error3)
  }

  func testKeychainErrorLocalizedDescription() {
    let error = KeychainError.itemNotFound
    XCTAssertEqual(error.localizedDescription, error.debugDescription)
    XCTAssertEqual(error.errorDescription, error.debugDescription)
  }

  // MARK: - Access Group Tests

  func testKeychainWithAccessGroup() {
    let keychainWithGroup = Keychain(service: testService, accessGroup: "group.com.supabase.test")
    XCTAssertNotNil(keychainWithGroup)
  }

  // MARK: - Multiple Keys Tests

  func testMultipleKeys() throws {
    let key1 = "test-key-1-\(UUID())"
    let key2 = "test-key-2-\(UUID())"
    let data1 = "Data 1".data(using: .utf8)!
    let data2 = "Data 2".data(using: .utf8)!

    defer {
      try? keychain.deleteItem(forKey: key1)
      try? keychain.deleteItem(forKey: key2)
    }

    // Set multiple keys
    try keychain.set(data1, forKey: key1)
    try keychain.set(data2, forKey: key2)

    // Retrieve and verify
    XCTAssertEqual(try keychain.data(forKey: key1), data1)
    XCTAssertEqual(try keychain.data(forKey: key2), data2)

    // Delete one key
    try keychain.deleteItem(forKey: key1)

    // Verify first is deleted, second still exists
    XCTAssertThrowsError(try keychain.data(forKey: key1))
    XCTAssertEqual(try keychain.data(forKey: key2), data2)
  }

  // MARK: - Empty Data Tests

  func testEmptyData() throws {
    let emptyData = Data()

    try keychain.set(emptyData, forKey: testKey)
    let retrieved = try keychain.data(forKey: testKey)

    XCTAssertEqual(retrieved, emptyData)
    XCTAssertEqual(retrieved.count, 0)
  }

  // MARK: - Large Data Tests

  func testLargeData() throws {
    // Create a large data blob (1MB)
    let largeData = Data(repeating: 0xFF, count: 1024 * 1024)

    try keychain.set(largeData, forKey: testKey)
    let retrieved = try keychain.data(forKey: testKey)

    XCTAssertEqual(retrieved, largeData)
    XCTAssertEqual(retrieved.count, largeData.count)
  }
}
#endif
