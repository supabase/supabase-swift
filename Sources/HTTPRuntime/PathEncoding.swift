//
//  PathEncoding.swift
//  HTTPRuntime
//
//  Created by Guilherme Souza on 08/07/26.
//
import Foundation

/// Percent-encoding for URL path parameters. Generated code calls these when
/// substituting `@httpLabel` values into a path template.
public enum PathEncoding {
  private static let segmentAllowed: CharacterSet = {
    var set = CharacterSet.urlPathAllowed
    set.remove("/")  // a single path segment must escape slashes
    return set
  }()

  /// Encodes a single path segment (escapes `/`).
  public static func segment(_ value: String) -> String {
    value.addingPercentEncoding(withAllowedCharacters: segmentAllowed) ?? value
  }

  /// Encodes a greedy label (`{path+}`) that may legitimately contain `/`.
  public static func greedy(_ value: String) -> String {
    value.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? value
  }
}
