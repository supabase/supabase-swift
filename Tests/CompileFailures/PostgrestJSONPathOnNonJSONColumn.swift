//
//  PostgrestJSONPathOnNonJSONColumn.swift
//  Supabase
//
//  Created by Guilherme Souza on 10/10/26.
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
