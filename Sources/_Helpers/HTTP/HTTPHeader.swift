//
//  HTTPHeader.swift
//
//
//  Created by Guilherme Souza on 23/04/24.
//

import Foundation

package struct HTTPHeaders {
  var fields: [HTTPHeader] = []

  package init() {}

  package init(_ fields: [HTTPHeader]) {
    self.fields = fields
  }

  package init(_ dicionary: [String: String]) {
    dicionary.forEach {
      update(name: $0, value: $1)
    }
  }

  package mutating func update(_ field: HTTPHeader) {
    if let index = fields.firstIndex(where: { $0.name.lowercased() == field.name.lowercased() }) {
      fields[index] = field
    } else {
      fields.append(field)
    }
  }

  package mutating func update(name: String, value: String) {
    update(HTTPHeader(name: name, value: value))
  }

  package mutating func remove(name: String) {
    fields.removeAll { $0.name.lowercased() == name.lowercased() }
  }

  package func value(for name: String) -> String? {
    fields
      .firstIndex(where: { $0.name.lowercased() == name.lowercased() })
      .map { fields[$0].value }
  }

  package subscript(_ name: String) -> String? {
    get {
      value(for: name)
    }
    set {
      if let newValue {
        update(name: name, value: newValue)
      } else {
        remove(name: name)
      }
    }
  }

  package subscript(_ name: String, default defaultValue: String) -> String {
    get {
      self[name] ?? defaultValue
    }
    set {
      self[name] = newValue
    }
  }

  package var dictionary: [String: String] {
    let namesAndValues = fields.map { ($0.name, $0.value) }
    return Dictionary(namesAndValues, uniquingKeysWith: { _, last in last })
  }

  package mutating func merge(with other: HTTPHeaders) {
    for field in other.fields {
      update(field)
    }
  }

  package func merged(with other: HTTPHeaders) -> HTTPHeaders {
    var copy = self
    copy.merge(with: other)
    return copy
  }
}

extension HTTPHeaders: ExpressibleByDictionaryLiteral {
  public init(dictionaryLiteral elements: (String, String)...) {
    elements.forEach { update(name: $0.0, value: $0.1) }
  }
}

extension HTTPHeaders: ExpressibleByArrayLiteral {
  package init(arrayLiteral elements: HTTPHeader...) {
    self.init(elements)
  }
}

// MARK: - Sequence

extension HTTPHeaders: Sequence {
  public func makeIterator() -> IndexingIterator<[HTTPHeader]> {
    fields.makeIterator()
  }
}

// MARK: - Collection

extension HTTPHeaders: Collection {
  public var startIndex: Int {
    fields.startIndex
  }

  public var endIndex: Int {
    fields.endIndex
  }

  public subscript(position: Int) -> HTTPHeader {
    fields[position]
  }

  public func index(after i: Int) -> Int {
    fields.index(after: i)
  }
}

// MARK: - CustomStringConvertible

extension HTTPHeaders: CustomStringConvertible {
  /// A textual representation of the headers.
  public var description: String {
    fields.map(\.description).joined(separator: "\n")
  }
}

package struct HTTPHeader: Sendable, Hashable {
  package let name: String
  package let value: String

  package init(name: String, value: String) {
    self.name = name
    self.value = value
  }
}

extension HTTPHeader: CustomStringConvertible {
  /// A textual representation of the header.
  package var description: String {
    "\(name): \(value)"
  }
}

extension HTTPHeaders: Equatable {
  package static func == (lhs: Self, rhs: Self) -> Bool {
    lhs.dictionary == rhs.dictionary
  }
}
