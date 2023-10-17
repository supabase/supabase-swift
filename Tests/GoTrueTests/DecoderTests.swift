import GoTrue
import SnapshotTesting
import XCTest

final class InMemoryLocalStorage: GoTrueLocalStorage, @unchecked Sendable {
  private let queue = DispatchQueue(label: "InMemoryLocalStorage")
  private var storage: [String: Data] = [:]

  func store(key: String, value: Data) throws {
    queue.sync {
      storage[key] = value
    }
  }

  func retrieve(key: String) throws -> Data? {
    queue.sync {
      storage[key]
    }
  }

  func remove(key: String) throws {
    queue.sync {
      storage[key] = nil
    }
  }
}

final class DecoderTests: XCTestCase {
  func testDecodeUser() {
    XCTAssertNoThrow(
      try JSONDecoder.goTrue.decode(User.self, from: json(named: "user"))
    )
  }

  func testDecodeSessionOrUser() {
    XCTAssertNoThrow(
      try JSONDecoder.goTrue.decode(
        AuthResponse.self, from: json(named: "session")
      )
    )
  }
}
