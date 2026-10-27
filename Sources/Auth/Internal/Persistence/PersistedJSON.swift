import Foundation

/// The JSON coding of the formats the client persists: the session and the PKCE flow records.
///
/// Dates are numbers, the seconds since 2001-01-01 00:00:00 UTC that `Date` itself stores, so a
/// value survives a save and a load unchanged. Seconds since 1970 would not: shifting the epoch
/// rounds away the lowest bit of some values.
enum PersistedJSON {
  static let encoder: JSONEncoder = {
    let encoder = JSONEncoder()
    encoder.outputFormatting = .sortedKeys
    encoder.dateEncodingStrategy = .deferredToDate
    return encoder
  }()

  static let decoder: JSONDecoder = {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .deferredToDate
    return decoder
  }()
}
