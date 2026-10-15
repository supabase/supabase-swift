//
//  PostgrestRangeFilterOnSiblingRangeType.swift
//  Supabase
//
//  Created by Guilherme Souza on 10/15/26.
//

// This file must NOT compile. It belongs to no target; `swift test` never sees it.
//
// `daterange` and `tstzrange` both hold dates, but each has its own bound marker, so a
// `daterange` operand on a `tstzrange` column is rejected here. Against the server Postgres would
// compare a date with a timestamp: it converts the value silently, or fails with `42883`.
//
// If this file ever compiles, two range types share a bound marker again.
// `scripts/check-compile-failures.sh` enforces it.
//
// expected-error: cannot convert value of type '_PostgresRange<_DateRange>' to expected argument type '_PostgresRange<_TSTZRange>'

@_spi(Experimental) import PostgREST

struct Booking: _PostgrestRelation {
  static let relationName = "bookings"
  static let selectString = "*"

  var id: Int

  struct Columns: Sendable {
    let stay = _PostgrestColumn<Booking, _PostgresRange<_TSTZRange>>("stay")
  }

  static let columns = Columns()
}

let forbidden = Booking.columns.stay.overlapsRange(
  _PostgresRange<_DateRange>("[2024-01-01,2024-02-01)"))
