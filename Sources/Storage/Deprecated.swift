//
//  Deprecated.swift
//
//
//  Created by Guilherme Souza on 16/01/24.
//

import Foundation

extension StorageClientConfiguration {
  @available(
    *,
    deprecated,
    message: "Replace usages of this initializer with new init(url:headers:encoder:decoder:session:logger)"
  )
  public init(
    url: URL,
    headers: [String: String],
    encoder: JSONEncoder = .defaultStorageEncoder,
    decoder: JSONDecoder = .defaultStorageDecoder,
    session: StorageHTTPSession = .init()
  ) {
    self.init(
      url: url,
      headers: headers,
      encoder: encoder,
      decoder: decoder,
      session: session,
      logger: nil
    )
  }
}
