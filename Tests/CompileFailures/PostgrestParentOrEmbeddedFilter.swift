//
//  PostgrestParentOrEmbeddedFilter.swift
//  Supabase
//
//  Created by Guilherme Souza on 09/10/26.
//

// expected-error: cannot convert value of type '_PostgrestFilter<Comment>' to expected argument type '_PostgrestFilter<Todo>'

@_spi(Experimental) import PostgREST

struct Todo: _PostgrestRelation {
  static let relationName = "todos"
  static let selectString = "*"

  var id: Int

  struct Columns: Sendable {
    let isDone = _PostgrestColumn<Todo, Bool>("is_done")
  }

  static let columns = Columns()
}

struct Comment: _PostgrestRelation {
  static let relationName = "comments"
  static let selectString = "*"

  var id: Int

  struct Columns: Sendable {
    let approved = _PostgrestColumn<Comment, Bool>("approved")
  }

  static let columns = Columns()
}

let forbidden = Todo.columns.isDone.eq(false) || Comment.columns.approved.eq(true)
