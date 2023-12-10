import Foundation
import SnapshotTesting
import XCTest

/// A platform aware version of the standard `assertSnapshot`
/// This is used to point to different subdirectories of the `__Snapshots__`
/// directory. On different platforms, the different textual representations
/// are different for a number of reasons, so this gives us a way to differentiate
/// where needed.
public func platformSpecificAssertSnapshot<Value, Format>(
  of value: @autoclosure () throws -> Value,
  as snapshotting: Snapshotting<Value, Format>,
  named name: String? = nil,
  record recording: Bool = false,
  timeout: TimeInterval = 5,
  file: StaticString = #file,
  testName: String = #function,
  line: UInt = #line
) {
    let fileUrl = URL(fileURLWithPath: "\(file)", isDirectory: false)
    let fileName = fileUrl.deletingPathExtension().lastPathComponent

    #if os(Linux)
    let platformDirectory = "linux"
    #elseif os(Windows)
    let platformDirectory = "windows"
    #else
    let platformDirectory = "darwin"
    #endif

    let snapshotDirectoryUrl = fileUrl
      .deletingLastPathComponent()
      .appendingPathComponent("__Snapshots__")
      .appendingPathComponent(fileName)
      .appendingPathComponent(platformDirectory)

    let failure = verifySnapshot(
      of: try value(),
      as: snapshotting,
      named: name,
      record: recording,
      snapshotDirectory: snapshotDirectoryUrl.path,
      timeout: timeout,
      file: file,
      testName: testName,
      line: line
    )
    guard let message = failure else { return }
    XCTFail(message, file: file, line: line)
}
