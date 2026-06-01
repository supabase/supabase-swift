//
//  RealtimeTable.swift
//  _Realtime
//
//  Created by Guilherme Souza on 24/04/25.
//

import Foundation

public protocol RealtimeTable {
  static var schema: String { get }
  static var tableName: String { get }
  static func columnName<V>(for keyPath: KeyPath<Self, V>) -> String
}

public protocol RealtimeFilterValue {
  var filterString: String { get }
}

extension String: RealtimeFilterValue { public var filterString: String { self } }
extension Int: RealtimeFilterValue { public var filterString: String { String(self) } }
extension Double: RealtimeFilterValue { public var filterString: String { String(self) } }
extension Bool: RealtimeFilterValue { public var filterString: String { String(self) } }
extension UUID: RealtimeFilterValue {
  public var filterString: String { uuidString.lowercased() }
}
