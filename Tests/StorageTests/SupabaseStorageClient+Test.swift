//
//  StorageClient+Test.swift
//
//
//  Created by Guilherme Souza on 04/11/23.
//

import Foundation
import Storage

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

extension StorageClient {
  static func test(
    supabaseURL: String,
    apiKey: String,
    session: URLSession = .shared
  ) -> StorageClient {
    StorageClient(
      url: URL(string: supabaseURL)!,
      configuration: StorageClientConfiguration(
        headers: [
          "Apikey": apiKey,
          "X-Client-Info": "storage-swift/x.y.z",
        ],
        session: session,
        logger: nil
      )
    )
  }
}
