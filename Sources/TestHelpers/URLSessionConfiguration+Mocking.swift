//
//  URLSessionConfiguration+Mocking.swift
//  Supabase
//
//  Created by Supabase on 18/12/25.
//

import Foundation
import Mocker

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

extension URLSessionConfiguration {
  /// A URL session configuration that routes requests through `Mocker`.
  package static func mocking() -> URLSessionConfiguration {
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [MockingURLProtocol.self]
    return config
  }
}
