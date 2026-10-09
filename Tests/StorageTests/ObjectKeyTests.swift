//
//  ObjectKeyTests.swift
//  Storage
//
//  Created by Guilherme Souza on 09/10/26.
//

import Foundation
import Testing

@testable import Storage

@Suite
struct ObjectKeyTests {
  @Test(
    arguments: [
      ("folder/file.png", "folder/file.png", "folder/file.png"),
      ("/folder//file.png/", "folder/file.png", "folder/file.png"),
      ("folder/my file.png", "folder/my file.png", "folder/my%20file.png"),
      ("a+b.png", "a+b.png", "a%2Bb.png"),
      ("a#b.png", "a#b.png", "a%23b.png"),
      ("a?b.png", "a?b.png", "a%3Fb.png"),
      ("100%.png", "100%.png", "100%25.png"),
      ("ünïcode/文件.png", "ünïcode/文件.png", "%C3%BCn%C3%AFcode/%E6%96%87%E4%BB%B6.png"),
      ("a;b=c&d.png", "a;b=c&d.png", "a;b=c&d.png"),
    ]
  )
  func normalizesAndEncodes(input: String, path: String, encoded: String) throws {
    let key = try ObjectKey(input)

    #expect(key.path == path)
    #expect(key.encoded == encoded)
  }

  @Test(arguments: ["", "/", "//"])
  func rejectsAnEmptyPath(input: String) {
    #expect {
      try ObjectKey(input)
    } throws: { error in
      (error as? StorageError)?.kind == .invalidRequest
    }
  }

  @Test(arguments: ["../secret.png", "folder/../file.png", "./file.png", "a/./b"])
  func rejectsDotSegments(input: String) {
    #expect {
      try ObjectKey(input)
    } throws: { error in
      (error as? StorageError)?.kind == .invalidRequest
    }
  }

  @Test
  func prefixMayBeEmpty() throws {
    #expect(try ObjectKey(prefix: "").path == "")
    #expect(try ObjectKey(prefix: "/").segments.isEmpty)
    #expect(try ObjectKey(prefix: "/folder//").path == "folder")
  }

  @Test
  func lenientKeepsDotSegmentsFullyEncoded() {
    let key = ObjectKey(lenient: "/a/../b/./c.png//")

    #expect(key.path == "a/../b/./c.png")
    #expect(key.encoded == "a/%2E%2E/b/%2E/c.png")
    #expect(ObjectKey(lenient: "/").segments.isEmpty)
  }

  @Test
  func encodesABucketIdAsOneSegment() {
    #expect(ObjectKey.encode("my bucket/x+y") == "my%20bucket%2Fx%2By")
  }
}
