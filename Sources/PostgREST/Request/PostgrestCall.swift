//
//  PostgrestCall.swift
//  PostgREST
//
//  Created by Guilherme Souza on 24/11/26.
//

import Foundation
import HTTPTypes

/// What a PostgREST call is about, as its client span and its duration metric record it: the
/// logical operation, and the table it targets or the function it calls.
struct PostgrestCall: Equatable, Sendable {
  enum Operation: String, Sendable {
    case select, insert, update, upsert, delete, rpc
  }

  var operation: Operation
  var table: String?
  var function: String?
}

extension _PostgrestRequest {
  /// Derived from the request, the way PostgREST reads it: a call to `rpc/{fn}` is `rpc` whatever
  /// the method, and a `PUT`, or a `POST` that asks for a `resolution=`, is an upsert.
  var call: PostgrestCall {
    if relation.hasPrefix("rpc/") {
      return PostgrestCall(operation: .rpc, function: String(relation.dropFirst("rpc/".count)))
    }
    let operation: PostgrestCall.Operation =
      switch method {
      case .post: resolvesDuplicates ? .upsert : .insert
      case .put: .upsert
      case .patch: .update
      case .delete: .delete
      default: .select
      }
    return PostgrestCall(operation: operation, table: relation)
  }

  private var resolvesDuplicates: Bool {
    headerFields[values: .prefer].contains { value in
      value.split(separator: ",").contains {
        $0.trimmingCharacters(in: .whitespaces).hasPrefix("resolution=")
      }
    }
  }
}
