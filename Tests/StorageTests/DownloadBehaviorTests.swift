//
//  DownloadBehaviorTests.swift
//  Storage
//

import Foundation
import Storage
import XCTest

final class DownloadBehaviorURLTests: XCTestCase {
  var bucket: StorageFileApi!

  override func setUp() {
    super.setUp()
    bucket = SupabaseStorageClient.test(
      supabaseURL: "http://localhost:54321/storage/v1",
      apiKey: "test-api-key"
    ).from("test-bucket")
  }

  func testGetPublicURL_noDownload() throws {
    let url = try bucket.getPublicURL(path: "image.png")
    let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
    let downloadItem = components?.queryItems?.first { $0.name == "download" }
    XCTAssertNil(downloadItem)
  }

  func testGetPublicURL_withOriginalName() throws {
    let url = try bucket.getPublicURL(path: "image.png", download: .withOriginalName)
    let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
    let downloadItem = components?.queryItems?.first { $0.name == "download" }
    XCTAssertEqual(downloadItem?.value, "")
  }

  func testGetPublicURL_namedDownload() throws {
    let url = try bucket.getPublicURL(path: "image.png", download: .named("photo.jpg"))
    let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
    let downloadItem = components?.queryItems?.first { $0.name == "download" }
    XCTAssertEqual(downloadItem?.value, "photo.jpg")
  }

  func testGetPublicURL_nilDownload() throws {
    let url = try bucket.getPublicURL(path: "image.png", download: Optional<DownloadBehavior>.none)
    let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
    let downloadItem = components?.queryItems?.first { $0.name == "download" }
    XCTAssertNil(downloadItem)
  }
}
