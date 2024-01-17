//
//  Deprecated.swift
//
//
//  Created by Guilherme Souza on 23/12/23.
//

import Foundation

@available(*, deprecated, renamed: "RealtimeMessage")
public typealias Message = RealtimeMessage

extension RealtimeChannelV2 {
//  @available(
//    *,
//    deprecated,
//    message: "Please use one of postgresChanges, presenceChange, or broadcast methods that returns an AsyncSequence instead."
//  )
//  @discardableResult
//  public func on(
//    _ event: String,
//    filter: ChannelFilter,
//    handler: @escaping (Message) -> Void
//  ) -> RealtimeChannel {
//    let stream: AsyncStream<HasRawMessage>
//
//    switch event.lowercased() {
//    case "postgres_changes":
//      switch filter.event?.uppercased() {
//      case "UPDATE":
//        stream = postgresChange(
//          UpdateAction.self,
//          schema: filter.schema ?? "public",
//          table: filter.table!,
//          filter: filter.filter
//        )
//        .map { $0 as HasRawMessage }
//        .eraseToStream()
//      case "INSERT":
//        stream = postgresChange(
//          InsertAction.self,
//          schema: filter.schema ?? "public",
//          table: filter.table!,
//          filter: filter.filter
//        )
//        .map { $0 as HasRawMessage }
//        .eraseToStream()
//      case "DELETE":
//        stream = postgresChange(
//          DeleteAction.self,
//          schema: filter.schema ?? "public",
//          table: filter.table!,
//          filter: filter.filter
//        )
//        .map { $0 as HasRawMessage }
//        .eraseToStream()
//      case "SELECT":
//        stream = postgresChange(
//          SelectAction.self,
//          schema: filter.schema ?? "public",
//          table: filter.table!,
//          filter: filter.filter
//        )
//        .map { $0 as HasRawMessage }
//        .eraseToStream()
//      default:
//        stream = postgresChange(
//          AnyAction.self,
//          schema: filter.schema ?? "public",
//          table: filter.table!,
//          filter: filter.filter
//        )
//        .map { $0 as HasRawMessage }
//        .eraseToStream()
//      }
//
//    case "presence":
//      stream = presenceChange().map { $0 as HasRawMessage }.eraseToStream()
//    case "broadcast":
//      stream = broadcast(event: filter.event!).map { $0 as HasRawMessage }.eraseToStream()
//    default:
//      fatalError(
//        "Unsupported event '\(event)'. Expected one of: postgres_changes, presence, or broadcast."
//      )
//    }
//
//    Task {
//      for await action in stream {
//        handler(action.rawMessage)
//      }
//    }
//
//    return self
//  }
}

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
