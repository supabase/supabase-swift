//
//  URLOpenerTests.swift
//  Supabase
//
//  Created by Coverage Tests
//

import Foundation
import Testing

@testable import Auth

@Suite
struct URLOpenerTests {

  // MARK: - Custom Opener Tests

  @Test
  func customURLOpener() async {
    final class Capture: @unchecked Sendable {
      var url: URL?
    }

    let capture = Capture()
    let customOpener = URLOpener { @Sendable url in
      capture.url = url
    }

    let testURL = URL(string: "https://example.com/callback")!

    await customOpener.open(testURL)

    #expect(capture.url == testURL)
  }

  @Test
  func customOpenerWithMultipleURLs() async {
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

    #expect(capture.urls.count == 3)
    #expect(capture.urls == urls)
  }

  @Test
  func customOpenerWithDifferentSchemes() async {
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

    #expect(capture.urls.count == schemes.count)
    for (index, url) in capture.urls.enumerated() {
      #expect(url.scheme == schemes[index])
    }
  }

  @Test
  func customOpenerWithQueryParameters() async {
    final class Capture: @unchecked Sendable {
      var url: URL?
    }

    let capture = Capture()
    let customOpener = URLOpener { @Sendable url in
      capture.url = url
    }

    let testURL = URL(string: "https://example.com/auth?code=123&state=abc")!

    await customOpener.open(testURL)

    #expect(capture.url?.scheme == "https")
    #expect(capture.url?.host == "example.com")
    #expect(capture.url?.path == "/auth")
    #expect(capture.url?.query?.contains("code=123") ?? false)
    #expect(capture.url?.query?.contains("state=abc") ?? false)
  }

  @Test
  func customOpenerWithFragment() async {
    final class Capture: @unchecked Sendable {
      var url: URL?
    }

    let capture = Capture()
    let customOpener = URLOpener { @Sendable url in
      capture.url = url
    }

    let testURL = URL(string: "https://example.com/page#section")!

    await customOpener.open(testURL)

    #expect(capture.url?.fragment == "section")
  }

  @Test
  func customOpenerWithComplexURL() async {
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

    #expect(capture.url == testURL)
    #expect(capture.url?.scheme == "myapp")
    #expect(capture.url?.host == "auth")
    #expect(capture.url?.path == "/callback")
    #expect(capture.url?.query != nil)
    #expect(capture.url?.fragment == "success")
  }

  // MARK: - Live Opener Tests

  @Test
  func liveOpenerExists() {
    let liveOpener = URLOpener.live
    #expect(liveOpener != nil)
  }

  @Test
  func liveOpenerStructure() async {
    // Test that live opener can be called without crashing
    // We can't really test if it opens URLs in a test environment,
    // but we can verify it compiles and runs
    let liveOpener = URLOpener.live
    let testURL = URL(string: "https://example.com")!

    // This will attempt to open the URL on the platform
    // In test environment, it might not succeed, but shouldn't crash
    await liveOpener.open(testURL)

    // If we get here, the function at least executed
    #expect(Bool(true))
  }

  // MARK: - Edge Cases

  @Test
  func openerWithURLWithPort() async {
    final class Capture: @unchecked Sendable {
      var url: URL?
    }

    let capture = Capture()
    let customOpener = URLOpener { @Sendable url in
      capture.url = url
    }

    let testURL = URL(string: "https://localhost:54321/auth/callback")!

    await customOpener.open(testURL)

    #expect(capture.url?.port == 54321)
    #expect(capture.url?.host == "localhost")
  }

  @Test
  func openerWithURLWithUsername() async {
    final class Capture: @unchecked Sendable {
      var url: URL?
    }

    let capture = Capture()
    let customOpener = URLOpener { @Sendable url in
      capture.url = url
    }

    let testURL = URL(string: "https://user@example.com/path")!

    await customOpener.open(testURL)

    #expect(capture.url?.user == "user")
  }

  @Test
  func openerWithEncodedURL() async {
    final class Capture: @unchecked Sendable {
      var url: URL?
    }

    let capture = Capture()
    let customOpener = URLOpener { @Sendable url in
      capture.url = url
    }

    let testURL = URL(string: "https://example.com/path?redirect=https%3A%2F%2Fother.com")!

    await customOpener.open(testURL)

    #expect(capture.url != nil)
    #expect(capture.url?.query?.contains("redirect=") ?? false)
  }

  // MARK: - Multiple Calls Tests

  @Test
  func multipleOpenerCalls() async {
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
    #expect(capturedURLs.count == 10)
  }

  // MARK: - Sendable Conformance Tests

  @Test
  func urlOpenerIsSendable() {
    let opener = URLOpener { @Sendable _ in }

    // Test that it can be used in async context
    Task {
      let url = URL(string: "https://example.com")!
      await opener.open(url)
    }
  }
}
