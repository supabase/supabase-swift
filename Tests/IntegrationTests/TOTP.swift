//
//  TOTP.swift
//  IntegrationTests
//
//  Created by Guilherme Souza on 16/11/26.
//

import Crypto
import Foundation
import Testing

/// RFC 6238 with the defaults GoTrue uses: SHA-1, 6 digits, a 30-second step.
func totpCode(secret: String, at date: Date = Date()) throws -> String {
  let key = try #require(base32Decode(secret))
  var counter = UInt64(date.timeIntervalSince1970 / 30).bigEndian
  let message = withUnsafeBytes(of: &counter) { Data($0) }

  let mac = Array(
    HMAC<Insecure.SHA1>.authenticationCode(for: message, using: SymmetricKey(data: key)))
  let offset = Int(mac[mac.count - 1] & 0x0f)
  let truncated =
    (UInt32(mac[offset] & 0x7f) << 24) | (UInt32(mac[offset + 1]) << 16)
    | (UInt32(mac[offset + 2]) << 8) | UInt32(mac[offset + 3])

  return String(format: "%06u", truncated % 1_000_000)
}

private func base32Decode(_ string: String) -> Data? {
  let alphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ234567")
  var buffer: UInt32 = 0
  var bitCount = 0
  var bytes: [UInt8] = []

  for character in string.uppercased() where character != "=" {
    guard let value = alphabet.firstIndex(of: character) else { return nil }
    buffer = (buffer << 5) | UInt32(value)
    bitCount += 5
    if bitCount >= 8 {
      bitCount -= 8
      bytes.append(UInt8((buffer >> UInt32(bitCount)) & 0xff))
    }
  }

  return Data(bytes)
}
