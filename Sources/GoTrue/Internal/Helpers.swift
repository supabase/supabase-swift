import Foundation

func extractParams(from fragment: String) -> [(name: String, value: String)] {
  let components =
    fragment
    .split(separator: "&")
    .map { $0.split(separator: "=") }

  return
    components
    .compactMap {
      $0.count == 2
        ? (name: String($0[0]), value: String($0[1]))
        : nil
    }
}

func decode(jwt: String) throws -> [String: Any] {
  let parts = jwt.split(separator: ".")
  guard parts.count == 3 else {
    throw GoTrueError.malformedJWT
  }

  let payload = String(parts[1])
  guard let data = base64URLDecode(payload) else {
    throw GoTrueError.malformedJWT
  }
  let json = try JSONSerialization.jsonObject(with: data, options: [])
  guard let decodedPayload = json as? [String: Any] else {
    throw GoTrueError.malformedJWT
  }
  return decodedPayload
}

private func base64URLDecode(_ value: String) -> Data? {
  var base64 = value.replacingOccurrences(of: "-", with: "+")
    .replacingOccurrences(of: "_", with: "/")
  let length = Double(base64.lengthOfBytes(using: .utf8))
  let requiredLength = 4 * ceil(length / 4.0)
  let paddingLength = requiredLength - length
  if paddingLength > 0 {
    let padding = "".padding(toLength: Int(paddingLength), withPad: "=", startingAt: 0)
    base64 = base64 + padding
  }
  return Data(base64Encoded: base64, options: .ignoreUnknownCharacters)
}
