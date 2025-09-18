//
//  SupabaseStorageClient+Test.swift
//
//
//  Created by Guilherme Souza on 04/11/23.
//

import Alamofire
import Foundation
import Storage

extension SupabaseStorageClient {
  static func test(
    supabaseURL: String,
    apiKey: String,
    session: Alamofire.Session = .default
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
        logger: nil
      )
    )
  }
}
