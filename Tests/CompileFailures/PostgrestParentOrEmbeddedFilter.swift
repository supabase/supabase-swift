//
//  PostgrestParentOrEmbeddedFilter.swift
//  Supabase
//
//  Created by Guilherme Souza on 09/10/26.
//

// This file must NOT compile. It belongs to no target; `swift test` never sees it.
//
// Spec §4.4: PostgREST cannot OR a parent filter against an embedded one. They are separate query
// parameters (`is_done=eq.false&comments.approved=eq.true`), so PostgREST always ANDs them. The
// typed API keeps that query out of reach: embedded scope lives on the query
// (`embedded`/`requiring`), and a `_PostgrestFilter<R>` only joins filters of the same `R`. A
// parent column and an embedded column therefore cannot meet under one `||`.
//
// If this file ever compiles, a refactor has given that property back: a filter tree can now mix
// relations, and the SDK would send a query whose meaning PostgREST does not support.
//
// Enforced, not only documented: `scripts/check-compile-failures.sh` type-checks this file against
// the built `PostgREST` module and fails unless the compiler rejects it with the expected
// diagnostic below. CI runs the script in the `spm` job. `swift test` alone does not catch a
// regression here.
//
// The guarantee covers the typed column API only. `_PostgrestFilter.raw` and the untyped
// `or("…")` still take any string, so they can spell the query; that is their job as escape
// hatches.
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

// "Todos that are not done, OR that have an approved comment" — the query PostgREST cannot run.
let forbidden = Todo.columns.isDone.eq(false) || Comment.columns.approved.eq(true)
