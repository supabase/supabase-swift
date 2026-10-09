//
//  PostgrestJSONPathOnNonJSONColumn.swift
//  Supabase
//
//  Created by Guilherme Souza on 10/10/26.
//

// This file must NOT compile. It belongs to no target; `swift test` never sees it.
//
// The JSON methods (`jsonText`, `jsonObject`, `containsJSON`, `containedByJSON`) need a column whose
// Swift type is `JSONValue`, which the generator emits for `json`/`jsonb` and nothing else. Against
// the server, a JSON path on an `interval` column is a `42883 operator does not exist`.
//
// If this file ever compiles, the JSON methods have lost their gate on `Value == JSONValue`, or a
// non-JSON Postgres type is generated as `JSONValue` again. `scripts/check-compile-failures.sh`
// enforces it.
//
// expected-error: referencing instance method 'jsonText' on '_PostgrestColumnExpression' requires the types '_PostgresInterval' and 'JSONValue' be equivalent

@_spi(Experimental) import PostgREST

struct Task: _PostgrestRelation {
  static let relationName = "tasks"
  static let selectString = "*"

  var id: Int

  struct Columns: Sendable {
    let estimate = _PostgrestColumn<Task, _PostgresInterval>("estimate")
  }

  static let columns = Columns()
}

let forbidden = Task.columns.estimate.jsonText("hours")
