//
//  MockExtensions.swift
//  Supabase
//
//  Created by Guilherme Souza on 21/01/25.
//

import Mocker
import Foundation
import InlineSnapshotTesting

extension Mock {
  package func snapshotRequest(
    message: @autoclosure () -> String = "",
    record: SnapshotTestingConfiguration.Record? = nil,
    timeout: TimeInterval = 5,
    syntaxDescriptor: InlineSnapshotSyntaxDescriptor = InlineSnapshotSyntaxDescriptor(),
    matches expected: (() -> String)? = nil,
    fileID: StaticString = #fileID,
    file filePath: StaticString = #filePath,
    function: StaticString = #function,
    line: UInt = #line,
    column: UInt = #column
  ) -> Self {
    var copy = self
    copy.onRequestHandler = OnRequestHandler {
      assertInlineSnapshot(
        of: $0,
        as: ._curl,
        record: record,
        timeout: timeout,
        syntaxDescriptor: syntaxDescriptor,
        matches: expected,
        fileID: fileID,
        file: filePath,
        function: function,
        line: line,
        column: column
      )
    }
    return copy
  }
}
