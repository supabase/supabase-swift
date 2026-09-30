//
//  PostgrestFilterOperator.swift
//  PostgREST
//
//  Created by Lukas Klingsbo on 08/09/26.
//

/// An operator of the typed filter API, and the token PostgREST reads it as.
///
/// Every operator method on ``PostgrestFilterableExpression`` builds its filter through one of
/// these cases, so the wire spelling of an operator is declared once, here, and a consumer that
/// maps a ``PostgrestFilter`` onto another representation switches over it exhaustively.
///
/// Closed on purpose: an operator this SDK has no case for goes through
/// ``PostgrestFilterableExpression/raw(_:)``, which sends the operand as written.
public enum PostgrestFilterOperator: Hashable, Sendable {
  /// Equals, `eq`.
  case eq

  /// Does not equal, `neq`.
  case neq

  /// Greater than, `gt`.
  case gt

  /// Greater than or equal to, `gte`.
  case gte

  /// Less than, `lt`.
  case lt

  /// Less than or equal to, `lte`.
  case lte

  /// `IS`, for the `null`, `true` and `false` checks, `is`.
  case `is`

  /// `IS DISTINCT FROM`, `isdistinct`.
  case isDistinct

  /// Membership in a `(a,b)` list, `in`.
  case `in`

  /// Case-sensitive `LIKE`, `like`.
  case like

  /// Case-insensitive `LIKE`, `ilike`.
  case ilike

  /// `LIKE` every pattern of an array, `like(all)`.
  case likeAllOf

  /// `LIKE` at least one pattern of an array, `like(any)`.
  case likeAnyOf

  /// `ILIKE` every pattern of an array, `ilike(all)`.
  case ilikeAllOf

  /// `ILIKE` at least one pattern of an array, `ilike(any)`.
  case ilikeAnyOf

  /// Case-sensitive POSIX regular expression match, `match`.
  case regexMatch

  /// Case-insensitive POSIX regular expression match, `imatch`.
  case regexIMatch

  /// Contains (`@>`), `cs`. The operand is an array, range or JSON literal by the column's type.
  case contains

  /// Contained by (`<@`), `cd`.
  case containedBy

  /// Overlaps (`&&`), `ov`.
  case overlaps

  /// Range strictly to the left of (`<<`), `sl`.
  case rangeLt

  /// Range strictly to the right of (`>>`), `sr`.
  case rangeGt

  /// Range does not extend to the left of (`&>`), `nxl`.
  case rangeGte

  /// Range does not extend to the right of (`&<`), `nxr`.
  case rangeLte

  /// Range adjacent to (`-|-`), `adj`.
  case rangeAdjacent

  /// Full-text search, `fts`, with the conversion prefix and the configuration folded into the
  /// token: `wfts(english)` for `type: .websearch` and `config: "english"`.
  case textSearch(config: String?, type: TextSearchType?)

  /// The operator as PostgREST reads it, between the column and the operand.
  public var token: String {
    switch self {
    case .eq: "eq"
    case .neq: "neq"
    case .gt: "gt"
    case .gte: "gte"
    case .lt: "lt"
    case .lte: "lte"
    case .is: "is"
    case .isDistinct: "isdistinct"
    case .in: "in"
    case .like: "like"
    case .ilike: "ilike"
    case .likeAllOf: "like(all)"
    case .likeAnyOf: "like(any)"
    case .ilikeAllOf: "ilike(all)"
    case .ilikeAnyOf: "ilike(any)"
    case .regexMatch: "match"
    case .regexIMatch: "imatch"
    case .contains: "cs"
    case .containedBy: "cd"
    case .overlaps: "ov"
    case .rangeLt: "sl"
    case .rangeGt: "sr"
    case .rangeGte: "nxl"
    case .rangeLte: "nxr"
    case .rangeAdjacent: "adj"
    case .textSearch(let config, let type):
      "\(type?.rawValue ?? "")fts\(config.map { "(\($0))" } ?? "")"
    }
  }
}
