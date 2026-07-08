//
//  HTTPMethod.swift
//  HTTPRuntime
//
//  Created by Guilherme Souza on 08/07/26.
//
// Part of the internal HTTP runtime. NEVER exposed as public SDK surface.

/// HTTP verbs supported by the generated operations.
public enum HTTPMethod: String, Sendable, Hashable {
  case get = "GET"
  case post = "POST"
  case put = "PUT"
  case patch = "PATCH"
  case delete = "DELETE"
  case head = "HEAD"
}
