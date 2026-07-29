//
//  SpecNormalization.swift
//

import Foundation

/// Pre-decode cleanup for constructs OpenAPIKit can't represent.
///
/// OpenAPIKit models `anyOf`/`oneOf` as a `.any`/`.one` schema with no
/// `ObjectContext`, so when a `anyOf`/`oneOf` made up entirely of
/// `{"required": [...]}` fragments sits alongside sibling `properties`/`type`
/// (an "at least one of these properties must be present" validation
/// constraint), the decoder picks the union branch and drops the properties
/// irrecoverably. There's no way to recover that post-decode, so strip the
/// validation-only union here and let the object schema decode intact.
public enum SpecNormalization {
  public static func dropValidationOnlyUnions(_ data: Data) throws -> Data {
    let json = try JSONSerialization.jsonObject(with: data)
    let normalized = (normalize(json) as? [String: Any]) ?? [:]
    return try JSONSerialization.data(withJSONObject: normalized)
  }

  private static func isRequiredOnlyFragment(_ value: Any) -> Bool {
    guard let object = value as? [String: Any], object.count == 1 else { return false }
    return object["required"] is [Any]
  }

  private static func normalize(_ node: Any) -> Any {
    if let array = node as? [Any] {
      return array.map(normalize)
    }
    guard let object = node as? [String: Any] else { return node }

    var result: [String: Any] = [:]
    for (key, value) in object {
      switch key {
      case "anyOf", "oneOf":
        // An object schema's `anyOf`/`oneOf` made up entirely of
        // `{"required": [...]}` fragments is an "at least/exactly one of
        // these properties must be present" validation constraint, not a
        // type union — OpenAPIKit has no representation for combining that
        // with sibling `properties`, so drop it (same as `minProperties`,
        // which the generator already doesn't model).
        guard let branches = value as? [Any], !branches.isEmpty,
          branches.allSatisfy(isRequiredOnlyFragment), object["properties"] != nil
        else {
          result[key] = normalize(value)
          continue
        }
      default:
        result[key] = normalize(value)
      }
    }
    return result
  }
}
