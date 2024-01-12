import Foundation
@_spi(Internal) import _Helpers

public class PostgrestFilterBuilder: PostgrestTransformBuilder {
  public enum Operator: String, CaseIterable {
    case eq, neq, gt, gte, lt, lte, like, ilike, `is`, `in`, cs, cd, sl, sr, nxl, nxr, adj, ov, fts,
         plfts, phfts, wfts
  }

  // MARK: - Filters

  public func not(_ column: String, operator op: Operator, value: URLQueryRepresentable)
    -> PostgrestFilterBuilder
  {
    mutableState.withValue {
      $0.request.query.append(URLQueryItem(
        name: column,
        value: "not.\(op.rawValue).\(value.queryValue)"
      ))
    }

    return self
  }

  public func or(_ filters: URLQueryRepresentable) -> PostgrestFilterBuilder {
    mutableState.withValue {
      $0.request.query.append(URLQueryItem(name: "or", value: "(\(filters.queryValue.queryValue))"))
    }
    return self
  }

  public func eq(_ column: String, value: URLQueryRepresentable) -> PostgrestFilterBuilder {
    mutableState.withValue {
      $0.request.query.append(URLQueryItem(name: column, value: "eq.\(value.queryValue)"))
    }
    return self
  }

  public func neq(_ column: String, value: URLQueryRepresentable) -> PostgrestFilterBuilder {
    mutableState.withValue {
      $0.request.query.append(URLQueryItem(name: column, value: "neq.\(value.queryValue)"))
    }
    return self
  }

  public func gt(_ column: String, value: URLQueryRepresentable) -> PostgrestFilterBuilder {
    mutableState.withValue {
      $0.request.query.append(URLQueryItem(name: column, value: "gt.\(value.queryValue)"))
    }
    return self
  }

  public func gte(_ column: String, value: URLQueryRepresentable) -> PostgrestFilterBuilder {
    mutableState.withValue {
      $0.request.query.append(URLQueryItem(name: column, value: "gte.\(value.queryValue)"))
    }
    return self
  }

  public func lt(_ column: String, value: URLQueryRepresentable) -> PostgrestFilterBuilder {
    mutableState.withValue {
      $0.request.query.append(URLQueryItem(name: column, value: "lt.\(value.queryValue)"))
    }
    return self
  }

  public func lte(_ column: String, value: URLQueryRepresentable) -> PostgrestFilterBuilder {
    mutableState.withValue {
      $0.request.query.append(URLQueryItem(name: column, value: "lte.\(value.queryValue)"))
    }
    return self
  }

  public func like(_ column: String, value: URLQueryRepresentable) -> PostgrestFilterBuilder {
    mutableState.withValue {
      $0.request.query.append(URLQueryItem(name: column, value: "like.\(value.queryValue)"))
    }
    return self
  }

  public func ilike(_ column: String, value: URLQueryRepresentable) -> PostgrestFilterBuilder {
    mutableState.withValue {
      $0.request.query.append(URLQueryItem(name: column, value: "ilike.\(value.queryValue)"))
    }
    return self
  }

  public func `is`(_ column: String, value: URLQueryRepresentable) -> PostgrestFilterBuilder {
    mutableState.withValue {
      $0.request.query.append(URLQueryItem(name: column, value: "is.\(value.queryValue)"))
    }
    return self
  }

  public func `in`(_ column: String, value: [URLQueryRepresentable]) -> PostgrestFilterBuilder {
    mutableState.withValue {
      $0.request.query.append(
        URLQueryItem(
          name: column,
          value: "in.(\(value.map(\.queryValue).joined(separator: ",")))"
        )
      )
    }
    return self
  }

  public func contains(_ column: String, value: URLQueryRepresentable) -> PostgrestFilterBuilder {
    mutableState.withValue {
      $0.request.query.append(URLQueryItem(name: column, value: "cs.\(value.queryValue)"))
    }
    return self
  }

  public func rangeLt(_ column: String, range: URLQueryRepresentable) -> PostgrestFilterBuilder {
    mutableState.withValue {
      $0.request.query.append(URLQueryItem(name: column, value: "sl.\(range.queryValue)"))
    }
    return self
  }

  public func rangeGt(_ column: String, range: URLQueryRepresentable) -> PostgrestFilterBuilder {
    mutableState.withValue {
      $0.request.query.append(URLQueryItem(name: column, value: "sr.\(range.queryValue)"))
    }
    return self
  }

  public func rangeGte(_ column: String, range: URLQueryRepresentable) -> PostgrestFilterBuilder {
    mutableState.withValue {
      $0.request.query.append(URLQueryItem(name: column, value: "nxl.\(range.queryValue)"))
    }
    return self
  }

  public func rangeLte(_ column: String, range: URLQueryRepresentable) -> PostgrestFilterBuilder {
    mutableState.withValue {
      $0.request.query.append(URLQueryItem(name: column, value: "nxr.\(range.queryValue)"))
    }
    return self
  }

  public func rangeAdjacent(
    _ column: String,
    range: URLQueryRepresentable
  ) -> PostgrestFilterBuilder {
    mutableState.withValue {
      $0.request.query.append(URLQueryItem(name: column, value: "adj.\(range.queryValue)"))
    }
    return self
  }

  public func overlaps(_ column: String, value: URLQueryRepresentable) -> PostgrestFilterBuilder {
    mutableState.withValue {
      $0.request.query.append(URLQueryItem(name: column, value: "ov.\(value.queryValue)"))
    }
    return self
  }

  public func textSearch(_ column: String, range: URLQueryRepresentable) -> PostgrestFilterBuilder {
    mutableState.withValue {
      $0.request.query.append(URLQueryItem(name: column, value: "adj.\(range.queryValue)"))
    }
    return self
  }

  public func textSearch(
    _ column: String, query: URLQueryRepresentable, config: String? = nil,
    type: TextSearchType? = nil
  ) -> PostgrestFilterBuilder {
    mutableState.withValue {
      $0.request.query.append(
        URLQueryItem(
          name: column, value: "\(type?.rawValue ?? "")fts\(config ?? "").\(query.queryValue)"
        )
      )
    }
    return self
  }

  public func fts(_ column: String, query: URLQueryRepresentable, config: String? = nil)
    -> PostgrestFilterBuilder
  {
    mutableState.withValue {
      $0.request.query.append(URLQueryItem(
        name: column,
        value: "fts\(config ?? "").\(query.queryValue)"
      ))
    }
    return self
  }

  public func plfts(_ column: String, query: URLQueryRepresentable, config: String? = nil)
    -> PostgrestFilterBuilder
  {
    mutableState.withValue {
      $0.request.query.append(URLQueryItem(
        name: column,
        value: "plfts\(config ?? "").\(query.queryValue)"
      ))
    }
    return self
  }

  public func phfts(_ column: String, query: URLQueryRepresentable, config: String? = nil)
    -> PostgrestFilterBuilder
  {
    mutableState.withValue {
      $0.request.query.append(URLQueryItem(
        name: column,
        value: "phfts\(config ?? "").\(query.queryValue)"
      ))
    }
    return self
  }

  public func wfts(_ column: String, query: URLQueryRepresentable, config: String? = nil)
    -> PostgrestFilterBuilder
  {
    mutableState.withValue {
      $0.request.query.append(URLQueryItem(
        name: column,
        value: "wfts\(config ?? "").\(query.queryValue)"
      ))
    }
    return self
  }

  public func filter(_ column: String, operator: Operator, value: URLQueryRepresentable)
    -> PostgrestFilterBuilder
  {
    mutableState.withValue {
      $0.request.query.append(URLQueryItem(
        name: column,
        value: "\(`operator`.rawValue).\(value.queryValue)"
      ))
    }
    return self
  }

  public func match(_ query: [String: URLQueryRepresentable]) -> PostgrestFilterBuilder {
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
