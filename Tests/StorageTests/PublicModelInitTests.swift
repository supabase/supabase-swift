//
//  PublicModelInitTests.swift
//  Storage
//

import Foundation
import Testing

// A plain `import Storage`, not `@testable`: the tests see only the public API, the way an app
// building fixtures and previews does.
import Storage

@Suite struct StoragePublicModelInitTests {
  private let url = URL(string: "https://example.com/upload")!

  @Test func signedUploadURLIsBuildableAndMutable() {
    var signed = SignedUploadURL(signedURL: url, path: "a.png", token: "t")
    signed.path = "b.png"
    #expect(signed.path == "b.png")
  }

  @Test func uploadedObjectIsMutable() {
    var object = UploadedObject(path: "a.png", fullPath: "bucket/a.png")
    object.path = "b.png"
    #expect(object.path == "b.png")
  }

  @Test func objectPageIsMutable() {
    var page = ObjectPage(objects: [])
    page.nextCursor = "next"
    #expect(page.hasNext)
  }

  @Test func transferProgressIsMutable() {
    var progress = TransferProgress(completedBytes: 1, totalBytes: 10)
    progress.completedBytes = 5
    #expect(progress.completedBytes == 5)
  }
}
