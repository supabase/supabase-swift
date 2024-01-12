import Foundation

// Borrowed from the Vapor project,
// https://github.com/vapor/vapor/blob/main/Sources/Vapor/Utilities/Array%2BRandom.swift#L14
extension FixedWidthInteger {
  static func random() -> Self {
    random(in: .min ... .max)
  }

  static func random(using generator: inout some RandomNumberGenerator) -> Self {
    random(in: .min ... .max, using: &generator)
  }
}

extension Array where Element: FixedWidthInteger {
  static func random(count: Int) -> [Element] {
    var array: [Element] = .init(repeating: 0, count: count)
    (0 ..< count).forEach { array[$0] = Element.random() }
    return array
  }

  static func random(count: Int, using generator: inout some RandomNumberGenerator) -> [Element] {
    var array: [Element] = .init(repeating: 0, count: count)
    (0 ..< count).forEach { array[$0] = Element.random(using: &generator) }
    return array
  }
}
