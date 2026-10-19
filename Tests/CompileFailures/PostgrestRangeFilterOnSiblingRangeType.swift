//
//  PostgrestRangeFilterOnSiblingRangeType.swift
//  Supabase
//
//  Created by Guilherme Souza on 10/15/26.
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
