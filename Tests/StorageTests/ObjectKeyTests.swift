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
      ("folder/file.png", "folder/file.png"),
      ("folder/my file.png", "folder/my%20file.png"),
      ("a+b.png", "a%2Bb.png"),
      ("a#b.png", "a%23b.png"),
      ("a?b.png", "a%3Fb.png"),
      ("100%.png", "100%25.png"),
      ("café/文件.png", "caf%C3%A9/%E6%96%87%E4%BB%B6.png"),
      ("a;b=c&d.png", "a;b=c&d.png"),
      ("~!$'()*,:@-_.png", "~!$'()*,:@-_.png"),
    ]
  )
  func encodesEachSegment(input: String, encoded: String) {
    let key = ObjectKey(input)

    #expect(key.path == input)
    #expect(key.encoded == encoded)
  }

  @Test(
    arguments: [
      ("", ""),
      ("/", "/"),
      ("/folder//file.png/", "/folder//file.png/"),
      ("a/../b/./c.png", "a/%2E%2E/b/%2E/c.png"),
      ("..", "%2E%2E"),
    ]
  )
  func keepsThePathAsWritten(input: String, encoded: String) {
    let key = ObjectKey(input)

    #expect(key.path == input)
    #expect(key.encoded == encoded)
  }

  @Test
  func encodesABucketIdAsOneSegment() {
    #expect(ObjectKey.encode("my bucket/x+y") == "my%20bucket%2Fx%2By")
  }
}
