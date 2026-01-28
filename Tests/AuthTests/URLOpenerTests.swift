//
//  URLOpenerTests.swift
//  Supabase
//
//  Created by Coverage Tests
//

import XCTest

@testable import Auth

final class URLOpenerTests: XCTestCase {

  // MARK: - Custom Opener Tests

  func testCustomURLOpener() async {
    final class Capture: @unchecked Sendable {
      var url: URL?
    }

    let capture = Capture()
    let customOpener = URLOpener { @Sendable url in
      capture.url = url
    }

    let testURL = URL(string: "https://example.com/callback")!

    await customOpener.open(testURL)

    XCTAssertEqual(capture.url, testURL)
  }

  func testCustomOpenerWithMultipleURLs() async {
    final class Capture: @unchecked Sendable {
      var urls: [URL] = []
    }

    let capture = Capture()
    let customOpener = URLOpener { @Sendable url in
      capture.urls.append(url)
    }

    let urls = [
      URL(string: "https://example.com/auth")!,
      URL(string: "https://example.com/callback")!,
      URL(string: "myapp://redirect")!,
    ]

    for url in urls {
      await customOpener.open(url)
    }

    XCTAssertEqual(capture.urls.count, 3)
    XCTAssertEqual(capture.urls, urls)
  }

  func testCustomOpenerWithDifferentSchemes() async {
    final class Capture: @unchecked Sendable {
      var urls: [URL] = []
    }

    let capture = Capture()
    let customOpener = URLOpener { @Sendable url in
      capture.urls.append(url)
    }

    let schemes = ["https", "http", "myapp", "supabase"]
    let urls = schemes.map { URL(string: "\($0)://example.com")! }

    for url in urls {
      await customOpener.open(url)
    }

    XCTAssertEqual(capture.urls.count, schemes.count)
    for (index, url) in capture.urls.enumerated() {
      XCTAssertEqual(url.scheme, schemes[index])
    }
  }

  func testCustomOpenerWithQueryParameters() async {
    final class Capture: @unchecked Sendable {
      var url: URL?
    }

    let capture = Capture()
    let customOpener = URLOpener { @Sendable url in
      capture.url = url
    }

    let testURL = URL(string: "https://example.com/auth?code=123&state=abc")!

    await customOpener.open(testURL)

    XCTAssertEqual(capture.url?.scheme, "https")
    XCTAssertEqual(capture.url?.host, "example.com")
    XCTAssertEqual(capture.url?.path, "/auth")
    XCTAssertTrue(capture.url?.query?.contains("code=123") ?? false)
    XCTAssertTrue(capture.url?.query?.contains("state=abc") ?? false)
  }

  func testCustomOpenerWithFragment() async {
    final class Capture: @unchecked Sendable {
      var url: URL?
    }

    let capture = Capture()
    let customOpener = URLOpener { @Sendable url in
      capture.url = url
    }

    let testURL = URL(string: "https://example.com/page#section")!

    await customOpener.open(testURL)

    XCTAssertEqual(capture.url?.fragment, "section")
  }

  func testCustomOpenerWithComplexURL() async {
    final class Capture: @unchecked Sendable {
      var url: URL?
    }

    let capture = Capture()
    let customOpener = URLOpener { @Sendable url in
      capture.url = url
    }

    let testURL = URL(
      string:
        "myapp://auth/callback?access_token=abc123&refresh_token=def456&expires_in=3600#success")!

    await customOpener.open(testURL)

    XCTAssertEqual(capture.url, testURL)
    XCTAssertEqual(capture.url?.scheme, "myapp")
    XCTAssertEqual(capture.url?.host, "auth")
    XCTAssertEqual(capture.url?.path, "/callback")
    XCTAssertNotNil(capture.url?.query)
    XCTAssertEqual(capture.url?.fragment, "success")
  }

  // MARK: - Live Opener Tests

  func testLiveOpenerExists() {
    let liveOpener = URLOpener.live
    XCTAssertNotNil(liveOpener)
  }

  func testLiveOpenerStructure() async {
    // Test that live opener can be called without crashing
    // We can't really test if it opens URLs in a test environment,
    // but we can verify it compiles and runs
    let liveOpener = URLOpener.live
    let testURL = URL(string: "https://example.com")!

    // This will attempt to open the URL on the platform
    // In test environment, it might not succeed, but shouldn't crash
    await liveOpener.open(testURL)

    // If we get here, the function at least executed
    XCTAssertTrue(true)
  }

  // MARK: - Edge Cases

  func testOpenerWithURLWithPort() async {
    final class Capture: @unchecked Sendable {
      var url: URL?
    }

    let capture = Capture()
    let customOpener = URLOpener { @Sendable url in
      capture.url = url
    }

    let testURL = URL(string: "https://localhost:54321/auth/callback")!

    await customOpener.open(testURL)

    XCTAssertEqual(capture.url?.port, 54321)
    XCTAssertEqual(capture.url?.host, "localhost")
  }

  func testOpenerWithURLWithUsername() async {
    final class Capture: @unchecked Sendable {
      var url: URL?
    }

    let capture = Capture()
    let customOpener = URLOpener { @Sendable url in
      capture.url = url
    }

    let testURL = URL(string: "https://user@example.com/path")!

    await customOpener.open(testURL)

    XCTAssertEqual(capture.url?.user, "user")
  }

  func testOpenerWithEncodedURL() async {
    final class Capture: @unchecked Sendable {
      var url: URL?
    }

    let capture = Capture()
    let customOpener = URLOpener { @Sendable url in
      capture.url = url
    }

    let testURL = URL(string: "https://example.com/path?redirect=https%3A%2F%2Fother.com")!

    await customOpener.open(testURL)

    XCTAssertNotNil(capture.url)
    XCTAssertTrue(capture.url?.query?.contains("redirect=") ?? false)
  }

  // MARK: - Multiple Calls Tests

  func testMultipleOpenerCalls() async {
    final class URLCapture: @unchecked Sendable {
      var urls: [URL] = []
      private let lock = NSLock()

      func append(_ url: URL) {
        lock.lock()
        defer { lock.unlock() }
        urls.append(url)
      }

      func getURLs() -> [URL] {
        lock.lock()
        defer { lock.unlock() }
        return urls
      }
    }

    let capture = URLCapture()
    let customOpener = URLOpener { @Sendable url in
      capture.append(url)
    }

    for i in 0..<10 {
      let url = URL(string: "https://example.com/\(i)")!
      await customOpener.open(url)
    }

    let capturedURLs = capture.getURLs()
    XCTAssertEqual(capturedURLs.count, 10)
  }

  // MARK: - Sendable Conformance Tests

  func testURLOpenerIsSendable() {
    let opener = URLOpener { @Sendable _ in }

    // Test that it can be used in async context
    Task {
      let url = URL(string: "https://example.com")!
      await opener.open(url)
    }
  }
}
