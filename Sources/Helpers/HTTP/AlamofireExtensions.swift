//
//  SessionAdapters.swift
//  Supabase
//
//  Created by Guilherme Souza on 26/08/25.
//

import Alamofire
import Foundation


extension Alamofire.Session {
  /// Create a new session with the same configuration but with some overridden properties.
  package func newSession(
    adapters: [any RequestAdapter] = []
  ) -> Alamofire.Session {
    return Alamofire.Session(
      session: session,
      delegate: delegate,
      rootQueue: rootQueue,
      startRequestsImmediately: startRequestsImmediately,
      requestQueue: requestQueue,
      serializationQueue: serializationQueue,
      interceptor: Interceptor(
        adapters: self.interceptor != nil ? [self.interceptor!] + adapters : adapters
      ),
      serverTrustManager: serverTrustManager,
      redirectHandler: redirectHandler,
      cachedResponseHandler: cachedResponseHandler,
      eventMonitors: [eventMonitor]
    )
  }
}

package struct DefaultHeadersRequestAdapter: RequestAdapter {
  let headers: HTTPHeaders

  package init(headers: HTTPHeaders) {
    self.headers = headers
  }

  package func adapt(
    _ urlRequest: URLRequest,
    for session: Alamofire.Session,
    completion: @escaping (Result<URLRequest, any Error>) -> Void
  ) {
    var urlRequest = urlRequest
    urlRequest.headers.merge(with: headers)
    completion(.success(urlRequest))
  }
}
