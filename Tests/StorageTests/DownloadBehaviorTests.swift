//
//  DownloadBehaviorTests.swift
//  Storage
//

import Foundation
import Storage
import Testing

@Suite struct DownloadBehaviorURLTests {
  let bucket = SupabaseStorageClient.test(
    supabaseURL: "http://localhost:54321/storage/v1",
    apiKey: "test-api-key"
  ).from("test-bucket")

  @Test func getPublicURL_noDownload() throws {
    let url = try bucket.getPublicURL(path: "image.png")
    let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
    let downloadItem = components?.queryItems?.first { $0.name == "download" }
    #expect(downloadItem == nil)
  }

  @Test func getPublicURL_withOriginalName() throws {
    let url = try bucket.getPublicURL(path: "image.png", download: .withOriginalName)
    let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
    let downloadItem = components?.queryItems?.first { $0.name == "download" }
    #expect(downloadItem?.value == "")
  }

  @Test func getPublicURL_namedDownload() throws {
    let url = try bucket.getPublicURL(path: "image.png", download: .named("photo.jpg"))
    let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
    let downloadItem = components?.queryItems?.first { $0.name == "download" }
    #expect(downloadItem?.value == "photo.jpg")
  }

  @Test func getPublicURL_nilDownload() throws {
    let url = try bucket.getPublicURL(path: "image.png", download: Optional<DownloadBehavior>.none)
    let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
    let downloadItem = components?.queryItems?.first { $0.name == "download" }
    #expect(downloadItem == nil)
  }
}
