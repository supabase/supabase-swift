//
//  PostgrestRangeFilterOnWrongColumn.swift
//  Supabase
//
//  Created by Guilherme Souza on 10/10/26.
//

// This file must NOT compile. It belongs to no target; `swift test` never sees it.
//
// A range filter takes a `_PostgresRange` of the column's own bound type, so an `int4range`
// operand on a `daterange` column is rejected here. Against the server the same filter is a
// `22P02`, and on a column that is not a range at all a `42883`.
//
// If this file ever compiles, the range filters have lost their gate on
// `Value == _PostgresRange<B>`. `scripts/check-compile-failures.sh` enforces it.
//
// expected-error: cannot convert value of type '_PostgresRange<Int>' to expected argument type '_PostgresRange<Date>'

@_spi(Experimental) import PostgREST
import Foundation

struct Booking: _PostgrestRelation {
  static let relationName = "bookings"
  static let selectString = "*"

  var id: Int

  struct Columns: Sendable {
    let stay = _PostgrestColumn<Booking, _PostgresRange<Date>>("stay")
  }

  static let columns = Columns()
}

let forbidden = Booking.columns.stay.overlapsRange(_PostgresRange<Int>("[1,10)"))
