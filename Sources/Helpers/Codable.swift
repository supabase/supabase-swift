//
//  Codable.swift
//  Supabase
//
//  Created by Guilherme Souza on 20/01/25.
//

import ConcurrencyExtras
public import Foundation
import IssueReporting

extension JSONDecoder {
  /// Returns a new decoder that reads dates the way Supabase services send them.
  ///
  /// Postgres writes a `timestamptz` as `2024-01-02T03:04:05.123456+00:00` and a `timestamp` with
  /// no offset. Foundation's `.iso8601` strategy reads neither: it rejects fractional seconds and
  /// a missing offset. This decoder reads ISO 8601 with or without fractional seconds, with an
  /// offset (`Z`, `+00`, or `+00:00`) or without one, and a `date` column (`2024-01-02`) as
  /// midnight UTC. It also reads the dates an Edge Function writes with `JSON.stringify`, such as
  /// `2024-01-02T03:04:05.123Z`. Other settings keep their Foundation defaults.
  ///
  /// Every module uses this decoder by default: database responses, Edge Function responses,
  /// Realtime broadcasts, Postgres change rows, and presence payloads. To change a setting, start
  /// from this decoder, so `Date` values still decode. Set it on a client, or pass it to one call:
  ///
  /// ```swift
  /// let decoder = JSONDecoder.supabase()
  /// decoder.keyDecodingStrategy = .convertFromSnakeCase
  /// let supabase = try SupabaseClient(
  ///   supabaseURL: url,
  ///   supabaseKey: key,
  ///   configuration: .init(
  ///     database: .init(decoder: decoder),
  ///     functions: .init(decoder: decoder)
  ///   )
  /// )
  ///
  /// let message = try broadcast.decode(as: ChatMessage.self, decoder: decoder)
  /// ```
  ///
  /// Each call returns a new instance, so a change to one decoder does not reach another.
  public static func supabase() -> JSONDecoder {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .custom { decoder in
      let container = try decoder.singleValueContainer()
      let string = try container.decode(String.self)

      if let date = string.date {
        return date
      }

      throw DecodingError.dataCorruptedError(
        in: container,
        debugDescription: "Invalid date format: \(string)"
      )
    }
    return decoder
  }
}
extension JSONEncoder {
  /// Returns a new encoder that writes dates the way Supabase services read them.
  ///
  /// It writes a `Date` as ISO 8601 in UTC with milliseconds, for example
  /// `2024-01-02T03:04:05.500Z`, which Postgres reads into `timestamp` and `timestamptz` columns.
  /// Foundation's `.iso8601` strategy drops the fractional seconds. Other settings keep their
  /// Foundation defaults.
  ///
  /// Every module uses this encoder by default: database request bodies, Edge Function JSON
  /// bodies, Realtime broadcasts, and presence payloads. To change a setting, start from this
  /// encoder, so `Date` values still encode the same way. Set it on a client, or pass it to one
  /// call:
  ///
  /// ```swift
  /// let encoder = JSONEncoder.supabase()
  /// encoder.keyEncodingStrategy = .convertToSnakeCase
  /// let supabase = try SupabaseClient(
  ///   supabaseURL: url,
  ///   supabaseKey: key,
  ///   configuration: .init(database: .init(encoder: encoder))
  /// )
  ///
  /// try await channel.broadcast(event: "move", payload: move, encoder: encoder)
  /// ```
  ///
  /// Each call returns a new instance, so a change to one encoder does not reach another.
  public static func supabase() -> JSONEncoder {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .custom { date, encoder in
      var container = encoder.singleValueContainer()
      let string = date.iso8601String
      try container.encode(string)
    }

    #if DEBUG
      if isTesting {
        encoder.outputFormatting = [.sortedKeys]
      }
    #endif

    return encoder
  }
}
