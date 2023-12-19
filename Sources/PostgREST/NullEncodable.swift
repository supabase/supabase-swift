//
//  NullEncodable.swift
//
//
//  Created by Guilherme Souza on 19/12/23.
//

import Foundation

@propertyWrapper
public struct NullEncodable<T>: Encodable where T: Encodable {
  public var wrappedValue: T?

  public init(wrappedValue: T? = nil) {
    self.wrappedValue = wrappedValue
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.singleValueContainer()

    if let wrappedValue {
      try container.encode(wrappedValue)
    } else {
      try container.encodeNil()
    }
  }
}

extension NullEncodable: Equatable where T: Equatable {}
extension NullEncodable: Hashable where T: Hashable {}

extension NullEncodable: Decodable where T: Decodable {
  public init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()

    if container.decodeNil() {
      self.init(wrappedValue: nil)
    } else {
      try self.init(wrappedValue: container.decode(T.self))
    }
  }
}
