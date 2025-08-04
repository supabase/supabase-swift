//===----------------------------------------------------------------------===//
//
// This source file is part of the SwiftOpenAPIGenerator open source project
//
// Copyright (c) 2023 Apple Inc. and the SwiftOpenAPIGenerator project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of SwiftOpenAPIGenerator project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

import Foundation
import HTTPTypesFoundation

extension HTTPFields: PrettyStringConvertible {
  var prettyDescription: String {
    sorted(by: {
      $0.name.canonicalName.localizedCompare($1.name.canonicalName) == .orderedAscending
    })
    .map { "\($0.name.canonicalName): \($0.value)" }.joined(separator: "; ")
  }
}

extension HTTPTypes.HTTPRequest: PrettyStringConvertible {
  var prettyDescription: String {
    "\(method.rawValue) \(url?.absoluteString.removingPercentEncoding ?? "<nil>") [\(headerFields.prettyDescription)]"
  }
}

extension HTTPTypes.HTTPResponse: PrettyStringConvertible {
  var prettyDescription: String { "\(status.code) \(status.reasonPhrase) [\(headerFields.prettyDescription)]" }
}

extension HTTPBody: PrettyStringConvertible {
  var prettyDescription: String { String(describing: self) }
}
