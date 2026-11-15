@testable import Storage

extension Fingerprint {
  /// A valid fingerprint made of `digit` repeated 64 times, so tests can name distinct uploads.
  static func repeating(_ digit: Character) -> Fingerprint {
    Fingerprint(rawValue: String(repeating: digit, count: 64))!
  }
}
