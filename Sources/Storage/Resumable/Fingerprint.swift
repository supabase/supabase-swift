import Foundation

public struct Fingerprint: Hashable, Sendable {
  public let value: String

  private static let fingerprintSeparator = "::"
  private static let fingerprintParts = 2

  private var parts: [String] {
    value.components(separatedBy: Self.fingerprintSeparator)
  }

  public var source: String {
    parts[0]
  }

  public var size: Int64 {
    Int64(parts[1]) ?? 0
  }

  public init(source: String, size: Int64) {
    self.value = "\(source)\(Self.fingerprintSeparator)\(size)"
  }

  public init?(value: String) {
    let parts = value.components(separatedBy: Self.fingerprintSeparator)
    guard parts.count == Self.fingerprintParts else { return nil }
    self.init(source: parts[0], size: Int64(parts[1]) ?? 0)
  }
}

extension Fingerprint: Codable {
  public init(from decoder: any Decoder) throws {
    let container = try decoder.singleValueContainer()
    let value = try container.decode(String.self)
    guard let fingerprint = Fingerprint(value: value) else {
      throw DecodingError.dataCorrupted(
        DecodingError.Context(
          codingPath: decoder.codingPath,
          debugDescription: "Invalid fingerprint format"
        )
      )
    }
    self = fingerprint
  }

  public func encode(to encoder: any Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(value)
  }
}

extension Fingerprint: CustomStringConvertible {
  public var description: String {
    value
  }
}