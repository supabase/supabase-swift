//
//  SessionAdapters.swift
//  Supabase
//
//  Created by Guilherme Souza on 26/08/25.
//

import Alamofire
import Foundation

package struct SupabaseApiKeyAdapter: RequestAdapter {

  let apiKey: String

  package init(apiKey: String) {
    self.apiKey = apiKey
  }

  package func adapt(
    _ urlRequest: URLRequest,
    for session: Session,
    completion: @escaping (Result<URLRequest, any Error>) -> Void
  ) {
    var urlRequest = urlRequest

    if urlRequest.value(forHTTPHeaderField: "apikey") == nil {
      urlRequest.setValue(apiKey, forHTTPHeaderField: "apikey")
    }

    if urlRequest.headers["Authorization"] == nil {
      urlRequest.headers.add(.authorization(bearerToken: apiKey))
    }

    completion(.success(urlRequest))
  }
}
