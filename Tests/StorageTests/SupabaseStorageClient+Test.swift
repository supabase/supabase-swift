//
//  StorageClient+Test.swift
//
//
//  Created by Guilherme Souza on 04/11/23.
//

import Foundation
import Storage

extension StorageClient {
  static func test(
    supabaseURL: String,
    apiKey: String,
    session: URLSession = .shared
  ) -> StorageClient {
    StorageClient(
      configuration: StorageClientConfiguration(
        url: URL(string: supabaseURL)!,
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
