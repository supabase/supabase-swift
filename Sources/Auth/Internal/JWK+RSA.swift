//
//  JWK+RSA.swift
//  Supabase
//
//  Created by Guilherme Souza on 07/10/25.
//

import Foundation

#if canImport(Security)

  extension JWK {
    var rsaPublishKey: SecKey? {
      guard kty == "RSA",
        alg == "RS256",
        let n,
        let modulus = Base64URL.decode(n),
        let e,
        let exponent = Base64URL.decode(e)
      else {
        return nil
      }

      let encodedKey = encodeRSAPublishKey(modulus: [UInt8](modulus), exponent: [UInt8](exponent))
      return generateRSAPublicKey(from: encodedKey)
    }
  }

  extension JWK {
    fileprivate func encodeRSAPublishKey(modulus: [UInt8], exponent: [UInt8]) -> Data {
      var prefixedModulus: [UInt8] = [0x00]  // To indicate that the number is not negative
      prefixedModulus.append(contentsOf: modulus)
      let encodedModulus = prefixedModulus.derEncode(as: 2)  // Integer
      let encodedExponent = exponent.derEncode(as: 2)  // Integer
      let encodedSequence = (encodedModulus + encodedExponent).derEncode(as: 48)  // Sequence
      return Data(encodedSequence)
    }

    fileprivate func generateRSAPublicKey(from derEncodedData: Data) -> SecKey? {
      let sizeInBits = derEncodedData.count * MemoryLayout<UInt8>.size
      let attributes: [CFString: Any] = [
        kSecAttrKeyType: kSecAttrKeyTypeRSA,
        kSecAttrKeyClass: kSecAttrKeyClassPublic,
        kSecAttrKeySizeInBits: NSNumber(value: sizeInBits),
        kSecAttrIsPermanent: false,
      ]
      return SecKeyCreateWithData(derEncodedData as CFData, attributes as CFDictionary, nil)
    }
  }

  extension [UInt8] {
    fileprivate func derEncode(as dataType: UInt8) -> [UInt8] {
      var encodedBytes: [UInt8] = [dataType]
      var numberOfBytes = count
      if numberOfBytes < 128 {
        encodedBytes.append(UInt8(numberOfBytes))
      } else {
        let lengthData = Data(
          bytes: &numberOfBytes,
          count: MemoryLayout.size(ofValue: numberOfBytes)
        )
        let lengthBytes = [UInt8](lengthData).filter({ $0 != 0 }).reversed()
        encodedBytes.append(UInt8(truncatingIfNeeded: lengthBytes.count) | 0b10000000)
        encodedBytes.append(contentsOf: lengthBytes)
      }
      encodedBytes.append(contentsOf: self)
      return encodedBytes
    }

  }

#endif
