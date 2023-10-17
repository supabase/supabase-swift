import Foundation

public class PostgrestFilterBuilder: PostgrestTransformBuilder {
  public enum Operator: String, CaseIterable {
    case eq, neq, gt, gte, lt, lte, like, ilike, `is`, `in`, cs, cd, sl, sr, nxl, nxr, adj, ov, fts,
      plfts, phfts, wfts
  }

  // MARK: - Filters

  public func not(column: String, operator op: Operator, value: URLQueryRepresentable)
    -> PostgrestFilterBuilder
  {
    appendSearchParams(name: column, value: "not.\(op.rawValue).\(value.queryValue)")
    return self
  }

  public func or(filters: URLQueryRepresentable) -> PostgrestFilterBuilder {
    appendSearchParams(name: "or", value: "(\(filters.queryValue.queryValue))")
    return self
  }

  public func eq(column: String, value: URLQueryRepresentable) -> PostgrestFilterBuilder {
    appendSearchParams(name: column, value: "eq.\(value.queryValue)")
    return self
  }

  public func neq(column: String, value: URLQueryRepresentable) -> PostgrestFilterBuilder {
    appendSearchParams(name: column, value: "neq.\(value.queryValue)")
    return self
  }

  public func gt(column: String, value: URLQueryRepresentable) -> PostgrestFilterBuilder {
    appendSearchParams(name: column, value: "gt.\(value.queryValue)")
    return self
  }

  public func gte(column: String, value: URLQueryRepresentable) -> PostgrestFilterBuilder {
    appendSearchParams(name: column, value: "gte.\(value.queryValue)")
    return self
  }

  public func lt(column: String, value: URLQueryRepresentable) -> PostgrestFilterBuilder {
    appendSearchParams(name: column, value: "lt.\(value.queryValue)")
    return self
  }

  public func lte(column: String, value: URLQueryRepresentable) -> PostgrestFilterBuilder {
    appendSearchParams(name: column, value: "lte.\(value.queryValue)")
    return self
  }

  public func like(column: String, value: URLQueryRepresentable) -> PostgrestFilterBuilder {
    appendSearchParams(name: column, value: "like.\(value.queryValue)")
    return self
  }

  public func ilike(column: String, value: URLQueryRepresentable) -> PostgrestFilterBuilder {
    appendSearchParams(name: column, value: "ilike.\(value.queryValue)")
    return self
  }

  public func `is`(column: String, value: URLQueryRepresentable) -> PostgrestFilterBuilder {
    appendSearchParams(name: column, value: "is.\(value.queryValue)")
    return self
  }

  public func `in`(column: String, value: [URLQueryRepresentable]) -> PostgrestFilterBuilder {
    appendSearchParams(
      name: column,
      value: "in.(\(value.map(\.queryValue).joined(separator: ",")))"
    )
    return self
  }

  public func contains(column: String, value: URLQueryRepresentable) -> PostgrestFilterBuilder {
    appendSearchParams(name: column, value: "cs.\(value.queryValue)")
    return self
  }

  public func rangeLt(column: String, range: URLQueryRepresentable) -> PostgrestFilterBuilder {
    appendSearchParams(name: column, value: "sl.\(range.queryValue)")
    return self
  }

  public func rangeGt(column: String, range: URLQueryRepresentable) -> PostgrestFilterBuilder {
    appendSearchParams(name: column, value: "sr.\(range.queryValue)")
    return self
  }

  public func rangeGte(column: String, range: URLQueryRepresentable) -> PostgrestFilterBuilder {
    appendSearchParams(name: column, value: "nxl.\(range.queryValue)")
    return self
  }

  public func rangeLte(column: String, range: URLQueryRepresentable) -> PostgrestFilterBuilder {
    appendSearchParams(name: column, value: "nxr.\(range.queryValue)")
    return self
  }

  public func rangeAdjacent(column: String, range: URLQueryRepresentable) -> PostgrestFilterBuilder
  {
    appendSearchParams(name: column, value: "adj.\(range.queryValue)")
    return self
  }

  public func overlaps(column: String, value: URLQueryRepresentable) -> PostgrestFilterBuilder {
    appendSearchParams(name: column, value: "ov.\(value.queryValue)")
    return self
  }

  public func textSearch(column: String, range: URLQueryRepresentable) -> PostgrestFilterBuilder {
    appendSearchParams(name: column, value: "adj.\(range.queryValue)")
    return self
  }

  public func textSearch(
    column: String, query: URLQueryRepresentable, config: String? = nil, type: TextSearchType? = nil
  ) -> PostgrestFilterBuilder {
    appendSearchParams(
      name: column, value: "\(type?.rawValue ?? "")fts\(config ?? "").\(query.queryValue)"
    )
    return self
  }

  public func fts(column: String, query: URLQueryRepresentable, config: String? = nil)
    -> PostgrestFilterBuilder
  {
    appendSearchParams(name: column, value: "fts\(config ?? "").\(query.queryValue)")
    return self
  }

  public func plfts(column: String, query: URLQueryRepresentable, config: String? = nil)
    -> PostgrestFilterBuilder
  {
    appendSearchParams(name: column, value: "plfts\(config ?? "").\(query.queryValue)")
    return self
  }

  public func phfts(column: String, query: URLQueryRepresentable, config: String? = nil)
    -> PostgrestFilterBuilder
  {
    appendSearchParams(name: column, value: "phfts\(config ?? "").\(query.queryValue)")
    return self
  }

  public func wfts(column: String, query: URLQueryRepresentable, config: String? = nil)
    -> PostgrestFilterBuilder
  {
    appendSearchParams(name: column, value: "wfts\(config ?? "").\(query.queryValue)")
    return self
  }

  public func filter(column: String, operator: Operator, value: URLQueryRepresentable)
    -> PostgrestFilterBuilder
  {
    appendSearchParams(name: column, value: "\(`operator`.rawValue).\(value.queryValue)")
    return self
  }

  public func match(query: [String: URLQueryRepresentable]) -> PostgrestFilterBuilder {
    query.forEach { key, value in
      appendSearchParams(name: key, value: "eq.\(value.queryValue)")
    }
    return self
  }

  // MARK: - Filter Semantic Improvements

  public func equals(column: String, value: String) -> PostgrestFilterBuilder {
    eq(column: column, value: value)
  }

  public func notEquals(column: String, value: String) -> PostgrestFilterBuilder {
    neq(column: column, value: value)
  }

  public func greaterThan(column: String, value: String) -> PostgrestFilterBuilder {
    gt(column: column, value: value)
  }

  public func greaterThanOrEquals(column: String, value: String) -> PostgrestFilterBuilder {
    gte(column: column, value: value)
  }

  public func lowerThan(column: String, value: String) -> PostgrestFilterBuilder {
    lt(column: column, value: value)
  }

  public func lowerThanOrEquals(column: String, value: String) -> PostgrestFilterBuilder {
    lte(column: column, value: value)
  }

  public func rangeLowerThan(column: String, range: String) -> PostgrestFilterBuilder {
    rangeLt(column: column, range: range)
  }

  public func rangeGreaterThan(column: String, value: String) -> PostgrestFilterBuilder {
    rangeGt(column: column, range: value)
  }

  public func rangeGreaterThanOrEquals(column: String, value: String) -> PostgrestFilterBuilder {
    rangeGte(column: column, range: value)
  }

  public func rangeLowerThanOrEquals(column: String, value: String) -> PostgrestFilterBuilder {
    rangeLte(column: column, range: value)
  }

  public func fullTextSearch(column: String, query: String, config: String? = nil)
    -> PostgrestFilterBuilder
  {
    fts(column: column, query: query, config: config)
  }

  public func plainToFullTextSearch(column: String, query: String, config: String? = nil)
    -> PostgrestFilterBuilder
  {
    plfts(column: column, query: query, config: config)
  }

  public func phraseToFullTextSearch(column: String, query: String, config: String? = nil)
    -> PostgrestFilterBuilder
  {
    phfts(column: column, query: query, config: config)
  }

  public func webFullTextSearch(column: String, query: String, config: String? = nil)
    -> PostgrestFilterBuilder
  {
    wfts(column: column, query: query, config: config)
  }
}
