//
//  HTTPTestSupport.swift
//  Supabase
//
//  Created by Supabase on 18/12/25.
//

import ConcurrencyExtras
import Foundation
import Mocker

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

package enum HTTPTestSupport {
  package enum Error: Swift.Error, Equatable {
    case missingURL
    case invalidURLComponents
  }

  package static func captureRequest(into box: LockIsolated<URLRequest?>) -> OnRequestHandler {
    OnRequestHandler(requestCallback: { request in
      box.withValue { $0 = request }
    })
  }

  package static func captureRequests(into box: LockIsolated<[URLRequest]>) -> OnRequestHandler {
    OnRequestHandler(requestCallback: { request in
      box.withValue { $0.append(request) }
    })
  }

  package static func requestBody(_ request: URLRequest) -> Data? {
    request.httpBody
      ?? request.httpBodyStream.map { Data(reading: $0, withBufferSize: UInt(16 * 1024)) }
  }

  package static func urlComponents(_ request: URLRequest) throws -> URLComponents {
    guard let url = request.url else { throw Error.missingURL }
    guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
      throw Error.invalidURLComponents
    }
    return components
  }

  package static func queryDictionary(_ request: URLRequest) throws -> [String: String] {
    let components = try urlComponents(request)
    return Dictionary(
      uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value ?? "") }
    )
  }

  package static func jsonObject(_ data: Data) throws -> Any {
    try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
  }
}
