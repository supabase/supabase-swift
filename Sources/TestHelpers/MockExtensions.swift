//
//  MockExtensions.swift
//  Supabase
//
//  Created by Guilherme Souza on 21/01/25.
//

package import Foundation
package import InlineSnapshotTesting
package import Mocker

extension Mock {
  package func snapshotRequest(
    message: @autoclosure () -> String = "",
    record isRecording: SnapshotTestingConfiguration.Record? = nil,
    timeout: TimeInterval = 5,
    syntaxDescriptor: InlineSnapshotSyntaxDescriptor = InlineSnapshotSyntaxDescriptor(),
    matches expected: (() -> String)? = nil,
    fileID: StaticString = #fileID,
    file filePath: StaticString = #filePath,
    function: StaticString = #function,
    line: UInt = #line,
    column: UInt = #column
  ) -> Self {
    #if os(Linux) || os(Android)
      // non-Darwin curl snapshots have a different Content-Length than expected
      return self
    #endif
    // The comparison cannot happen in the handler below: Mocker calls it from the URL-loading
    // queue, where Swift Testing has no current test, so a recorded issue is dropped and the
    // assertion silently passes whatever the request was. Register the expectation here -- on the
    // test's task -- and let `MockerSerializedTrait` compare it once the body returns.
    let token = PendingRequestSnapshotStore.shared.register(
      PendingRequestSnapshot(
        expected: expected?(),
        message: message(),
        isRecording: isRecording,
        timeout: timeout,
        syntaxDescriptor: syntaxDescriptor,
        fileID: fileID,
        filePath: filePath,
        function: function,
        line: line,
        column: column,
        request: nil
      )
    )

    var copy = self
    copy.onRequestHandler = OnRequestHandler {
      PendingRequestSnapshotStore.shared.attach($0, to: token)
    }
    return copy
  }
}
