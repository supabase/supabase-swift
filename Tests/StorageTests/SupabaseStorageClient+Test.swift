//
//  SupabaseStorageClient+Test.swift
//
//
//  Created by Guilherme Souza on 04/11/23.
//

import Foundation
import Storage

extension SupabaseStorageClient {
  static func test(
    supabaseURL: String,
    apiKey: String,
    session: StorageHTTPSession = .init()
  ) -> SupabaseStorageClient {
    SupabaseStorageClient(
      configuration: StorageClientConfiguration(
        url: URL(string: supabaseURL)!,
        headers: [
          "Authorization": "Bearer \(apiKey)",
          "Apikey": apiKey,
          "X-Client-Info": "storage-swift/x.y.z",
        ],
        session: session,
        resumableSessionConfiguration: .default,
        logger: nil
      )
    )
  }
}
