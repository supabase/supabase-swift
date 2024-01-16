//
//  Deprecated.swift
//
//
//  Created by Guilherme Souza on 16/01/24.
//

import Foundation

extension RealtimeClient {
  @available(
    *,
    deprecated,
    message: "Replace usages of this initializer with new init(_:headers:params:vsn:logger)"
  )
  @available(macOS 10.15, iOS 13, watchOS 6, tvOS 13, *)
  public convenience init(
    _ endPoint: String,
    headers: [String: String] = [:],
    params: Payload? = nil,
    vsn: String = Defaults.vsn
  ) {
    self.init(endPoint, headers: headers, params: params, vsn: vsn, logger: nil)
  }

  @available(
    *,
    deprecated,
    message: "Replace usages of this initializer with new init(_:headers:paramsClosure:vsn:logger)"
  )
  @available(macOS 10.15, iOS 13, watchOS 6, tvOS 13, *)
  public convenience init(
    _ endPoint: String,
    headers: [String: String] = [:],
    paramsClosure: PayloadClosure?,
    vsn: String = Defaults.vsn
  ) {
    self.init(
      endPoint,
      headers: headers, paramsClosure: paramsClosure,
      vsn: vsn,
      logger: nil
    )
  }

  @available(
    *,
    deprecated,
    message: "Replace usages of this initializer with new init(endPoint:headers:transport:paramsClosure:vsn:logger)"
  )
  public convenience init(
    endPoint: String,
    headers: [String: String] = [:],
    transport: @escaping ((URL) -> PhoenixTransport),
    paramsClosure: PayloadClosure? = nil,
    vsn: String = Defaults.vsn
  ) {
    self.init(
      endPoint: endPoint,
      headers: headers,
      transport: transport,
      paramsClosure: paramsClosure,
      vsn: vsn,
      logger: nil
    )
  }
}
