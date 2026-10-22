//
//  PostgrestRangeFilterOnWrongColumn.swift
//  Supabase
//
//  Created by Guilherme Souza on 10/10/26.
//

// expected-error: cannot convert value of type '_PostgresRange<_Int4Range>' to expected argument type '_PostgresRange<_DateRange>'

@_spi(Experimental) import PostgREST

struct Booking: _PostgrestRelation {
  static let relationName = "bookings"
  static let selectString = "*"

  var id: Int

  struct Columns: Sendable {
    let stay = _PostgrestColumn<Booking, _PostgresRange<_DateRange>>("stay")
  }

  static let columns = Columns()
}

let forbidden = Booking.columns.stay.overlapsRange(_PostgresRange<_Int4Range>("[1,10)"))
