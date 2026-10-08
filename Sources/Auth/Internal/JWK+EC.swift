import Crypto
import Foundation

extension JWK {
  var p256PublicKey: P256.Signing.PublicKey? {
    guard kty == "EC",
      crv == "P-256",
      let x,
      let xData = Base64URL.decode(x),
      let y,
      let yData = Base64URL.decode(y),
      xData.count == 32,
      yData.count == 32
    else {
      return nil
    }

    return try? P256.Signing.PublicKey(x963Representation: Data([0x04]) + xData + yData)
  }
}
