import _Helpers
import Foundation

public class PostgrestFilterBuilder: PostgrestTransformBuilder {
  public enum Operator: String, CaseIterable, Sendable {
    case eq, neq, gt, gte, lt, lte, like, ilike, `is`, `in`, cs, cd, sl, sr, nxl, nxr, adj, ov, fts,
         plfts, phfts, wfts
  }

  // MARK: - Filters

  public func not(_ column: String, operator op: Operator, value: any URLQueryRepresentable)
    -> PostgrestFilterBuilder
  {
    let queryValue = value.queryValue

    mutableState.withValue {
      $0.request.query.append(URLQueryItem(
        name: column,
        value: "not.\(op.rawValue).\(queryValue)"
      ))
    }

    return self
  }

  public func or(
    _ filters: any URLQueryRepresentable,
    referencedTable: String? = nil
  ) -> PostgrestFilterBuilder {
    let key = referencedTable.map { "\($0).or" } ?? "or"
    let queryValue = filters.queryValue
    mutableState.withValue {
      $0.request.query.append(URLQueryItem(name: key, value: "(\(queryValue))"))
    }
    return self
  }

  public func eq(_ column: String, value: any URLQueryRepresentable) -> PostgrestFilterBuilder {
    let queryValue = value.queryValue
    mutableState.withValue {
      $0.request.query.append(URLQueryItem(name: column, value: "eq.\(queryValue)"))
    }
    return self
  }

  public func neq(_ column: String, value: any URLQueryRepresentable) -> PostgrestFilterBuilder {
    let queryValue = value.queryValue
    mutableState.withValue {
      $0.request.query.append(URLQueryItem(name: column, value: "neq.\(queryValue)"))
    }
    return self
  }

  public func gt(_ column: String, value: any URLQueryRepresentable) -> PostgrestFilterBuilder {
    let queryValue = value.queryValue
    mutableState.withValue {
      $0.request.query.append(URLQueryItem(name: column, value: "gt.\(queryValue)"))
    }
    return self
  }

  public func gte(_ column: String, value: any URLQueryRepresentable) -> PostgrestFilterBuilder {
    let queryValue = value.queryValue
    mutableState.withValue {
      $0.request.query.append(URLQueryItem(name: column, value: "gte.\(queryValue)"))
    }
    return self
  }

  public func lt(_ column: String, value: any URLQueryRepresentable) -> PostgrestFilterBuilder {
    let queryValue = value.queryValue
    mutableState.withValue {
      $0.request.query.append(URLQueryItem(name: column, value: "lt.\(queryValue)"))
    }
    return self
  }

  public func lte(_ column: String, value: any URLQueryRepresentable) -> PostgrestFilterBuilder {
    let queryValue = value.queryValue
    mutableState.withValue {
      $0.request.query.append(URLQueryItem(name: column, value: "lte.\(queryValue)"))
    }
    return self
  }

  public func like(_ column: String, value: any URLQueryRepresentable) -> PostgrestFilterBuilder {
    let queryValue = value.queryValue
    mutableState.withValue {
      $0.request.query.append(URLQueryItem(name: column, value: "like.\(queryValue)"))
    }
    return self
  }

  public func ilike(_ column: String, value: any URLQueryRepresentable) -> PostgrestFilterBuilder {
    let queryValue = value.queryValue
    mutableState.withValue {
      $0.request.query.append(URLQueryItem(name: column, value: "ilike.\(queryValue)"))
    }
    return self
  }

  public func `is`(_ column: String, value: any URLQueryRepresentable) -> PostgrestFilterBuilder {
    let queryValue = value.queryValue
    mutableState.withValue {
      $0.request.query.append(URLQueryItem(name: column, value: "is.\(queryValue)"))
    }
    return self
  }

  public func `in`(_ column: String, value: [any URLQueryRepresentable]) -> PostgrestFilterBuilder {
    let queryValue = value.map(\.queryValue)
    mutableState.withValue {
      $0.request.query.append(
        URLQueryItem(
          name: column,
          value: "in.(\(queryValue.joined(separator: ",")))"
        )
      )
    }
    return self
  }

  public func contains(
    _ column: String,
    value: any URLQueryRepresentable
  ) -> PostgrestFilterBuilder {
    let queryValue = value.queryValue
    mutableState.withValue {
      $0.request.query.append(URLQueryItem(name: column, value: "cs.\(queryValue)"))
    }
    return self
  }

  public func rangeLt(
    _ column: String,
    range: any URLQueryRepresentable
  ) -> PostgrestFilterBuilder {
    let queryValue = range.queryValue
    mutableState.withValue {
      $0.request.query.append(URLQueryItem(name: column, value: "sl.\(queryValue)"))
    }
    return self
  }

  public func rangeGt(
    _ column: String,
    range: any URLQueryRepresentable
  ) -> PostgrestFilterBuilder {
    let queryValue = range.queryValue
    mutableState.withValue {
      $0.request.query.append(URLQueryItem(name: column, value: "sr.\(queryValue)"))
    }
    return self
  }

  public func rangeGte(
    _ column: String,
    range: any URLQueryRepresentable
  ) -> PostgrestFilterBuilder {
    let queryValue = range.queryValue
    mutableState.withValue {
      $0.request.query.append(URLQueryItem(name: column, value: "nxl.\(queryValue)"))
    }
    return self
  }

  public func rangeLte(
    _ column: String,
    range: any URLQueryRepresentable
  ) -> PostgrestFilterBuilder {
    let queryValue = range.queryValue
    mutableState.withValue {
      $0.request.query.append(URLQueryItem(name: column, value: "nxr.\(queryValue)"))
    }
    return self
  }

  public func rangeAdjacent(
    _ column: String,
    range: any URLQueryRepresentable
  ) -> PostgrestFilterBuilder {
    let queryValue = range.queryValue
    mutableState.withValue {
      $0.request.query.append(URLQueryItem(name: column, value: "adj.\(queryValue)"))
    }
    return self
  }

  public func overlaps(
    _ column: String,
    value: any URLQueryRepresentable
  ) -> PostgrestFilterBuilder {
    let queryValue = value.queryValue
    mutableState.withValue {
      $0.request.query.append(URLQueryItem(name: column, value: "ov.\(queryValue)"))
    }
    return self
  }

  public func textSearch(
    _ column: String,
    value: any URLQueryRepresentable
  ) -> PostgrestFilterBuilder {
    let queryValue = value.queryValue
    mutableState.withValue {
      $0.request.query.append(URLQueryItem(name: column, value: "adj.\(queryValue)"))
    }
    return self
  }

  public func textSearch(
    _ column: String,
    query: any URLQueryRepresentable,
    config: String? = nil,
    type: TextSearchType? = nil
  ) -> PostgrestFilterBuilder {
    let queryValue = query.queryValue
    mutableState.withValue {
      $0.request.query.append(
        URLQueryItem(
          name: column, value: "\(type?.rawValue ?? "")fts\(config ?? "").\(queryValue)"
        )
      )
    }
    return self
  }

  public func fts(
    _ column: String,
    query: any URLQueryRepresentable,
    config: String? = nil
  ) -> PostgrestFilterBuilder {
    let queryValue = query.queryValue
    mutableState.withValue {
      $0.request.query.append(URLQueryItem(
        name: column,
        value: "fts\(config ?? "").\(queryValue)"
      ))
    }
    return self
  }

  public func plfts(
    _ column: String,
    query: any URLQueryRepresentable,
    config: String? = nil
  ) -> PostgrestFilterBuilder {
    let queryValue = query.queryValue
    mutableState.withValue {
      $0.request.query.append(URLQueryItem(
        name: column,
        value: "plfts\(config ?? "").\(queryValue)"
      ))
    }
    return self
  }

  public func phfts(
    _ column: String,
    query: any URLQueryRepresentable,
    config: String? = nil
  ) -> PostgrestFilterBuilder {
    let queryValue = query.queryValue
    mutableState.withValue {
      $0.request.query.append(URLQueryItem(
        name: column,
        value: "phfts\(config ?? "").\(queryValue)"
      ))
    }
    return self
  }

  public func wfts(
    _ column: String,
    query: any URLQueryRepresentable,
    config: String? = nil
  ) -> PostgrestFilterBuilder {
    let queryValue = query.queryValue
    mutableState.withValue {
      $0.request.query.append(URLQueryItem(
        name: column,
        value: "wfts\(config ?? "").\(queryValue)"
      ))
    }
    return self
  }

  public func filter(
    _ column: String,
    operator: Operator,
    value: any URLQueryRepresentable
  ) -> PostgrestFilterBuilder {
    let queryValue = value.queryValue
    mutableState.withValue {
      $0.request.query.append(URLQueryItem(
        name: column,
        value: "\(`operator`.rawValue).\(queryValue)"
      ))
    }
    return self
  }

  public func match(_ query: [String: any URLQueryRepresentable]) -> PostgrestFilterBuilder {
    let query = query.mapValues(\.queryValue)
    mutableState.withValue { mutableState in
      for (key, value) in query {
        mutableState.request.query.append(URLQueryItem(
          name: key,
          value: "eq.\(value.queryValue)"
        ))
      }
    }
    return self
  }

  // MARK: - Filter Semantic Improvements

  public func equals(_ column: String, value: String) -> PostgrestFilterBuilder {
    eq(column, value: value)
  }

  public func notEquals(_ column: String, value: String) -> PostgrestFilterBuilder {
    neq(column, value: value)
  }

  public func greaterThan(_ column: String, value: String) -> PostgrestFilterBuilder {
    gt(column, value: value)
  }

  public func greaterThanOrEquals(_ column: String, value: String) -> PostgrestFilterBuilder {
    gte(column, value: value)
  }

  public func lowerThan(_ column: String, value: String) -> PostgrestFilterBuilder {
    lt(column, value: value)
  }

  public func lowerThanOrEquals(_ column: String, value: String) -> PostgrestFilterBuilder {
    lte(column, value: value)
  }

  public func rangeLowerThan(_ column: String, range: String) -> PostgrestFilterBuilder {
    rangeLt(column, range: range)
  }

  public func rangeGreaterThan(_ column: String, value: String) -> PostgrestFilterBuilder {
    rangeGt(column, range: value)
  }

  public func rangeGreaterThanOrEquals(_ column: String, value: String) -> PostgrestFilterBuilder {
    rangeGte(column, range: value)
  }

  public func rangeLowerThanOrEquals(_ column: String, value: String) -> PostgrestFilterBuilder {
    rangeLte(column, range: value)
  }

  public func fullTextSearch(_ column: String, query: String, config: String? = nil)
    -> PostgrestFilterBuilder
  {
    fts(column, query: query, config: config)
  }

  public func plainToFullTextSearch(_ column: String, query: String, config: String? = nil)
    -> PostgrestFilterBuilder
  {
    plfts(column, query: query, config: config)
  }

  public func phraseToFullTextSearch(_ column: String, query: String, config: String? = nil)
    -> PostgrestFilterBuilder
  {
    phfts(column, query: query, config: config)
  }

  public func webFullTextSearch(_ column: String, query: String, config: String? = nil)
    -> PostgrestFilterBuilder
  {
    wfts(column, query: query, config: config)
  }
}
