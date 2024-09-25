import Foundation
import Helpers

public final class PostgrestQueryBuilder: PostgrestBuilder, @unchecked Sendable {
  /// Perform a SELECT query on the table or view.
  /// - Parameters:
  ///   - columns: The columns to retrieve, separated by commas. Columns can be renamed when returned with `customName:columnName`
  ///   - head: When set to `true`, `data` will not be returned. Useful if you only need the count.
  ///   - count: Count algorithm to use to count rows in the table or view.
  public func select(
    _ columns: String = "*",
    head: Bool = false,
    count: CountOption? = nil
  ) -> PostgrestFilterBuilder {
    mutableState.withValue {
      $0.request.method = .get
      // remove whitespaces except when quoted.
      var quoted = false
      let cleanedColumns = columns.compactMap { char -> String? in
        if char.isWhitespace, !quoted {
          return nil
        }
        if char == "\"" {
          quoted = !quoted
        }
        return String(char)
      }
      .joined(separator: "")

      $0.request.query.appendOrUpdate(URLQueryItem(name: "select", value: cleanedColumns))

      if let count {
        $0.request.headers["Prefer"] = "count=\(count.rawValue)"
      }
      if head {
        $0.request.method = .head
      }
    }

    return PostgrestFilterBuilder(self)
  }

  /// Performs an INSERT into the table or view.
  ///
  /// By default, inserted rows are not returned. To return it, chain the call with `.select()`.
  ///
  /// - Parameters:
  ///   - values: The values to insert. Pass an object to insert a single row or an array to insert multiple rows.
  ///   - count: Count algorithm to use to count inserted rows.
  public func insert(
    _ values: some Encodable & Sendable,
    returning: PostgrestReturningOptions? = nil,
    count: CountOption? = nil
  ) throws -> PostgrestFilterBuilder {
    try mutableState.withValue {
      $0.request.method = .post
      var prefersHeaders: [String] = []
      if let returning {
        prefersHeaders.append("return=\(returning.rawValue)")
      }
      $0.request.body = try configuration.encoder.encode(values)
      if let count {
        prefersHeaders.append("count=\(count.rawValue)")
      }
      if let prefer = $0.request.headers["Prefer"] {
        prefersHeaders.insert(prefer, at: 0)
      }
      if !prefersHeaders.isEmpty {
        $0.request.headers["Prefer"] = prefersHeaders.joined(separator: ",")
      }
      if let body = $0.request.body,
         let jsonObject = try JSONSerialization.jsonObject(with: body) as? [[String: Any]]
      {
        let allKeys = jsonObject.flatMap(\.keys)
        let uniqueKeys = Set(allKeys).sorted()
        $0.request.query.appendOrUpdate(URLQueryItem(
          name: "columns",
          value: uniqueKeys.joined(separator: ",")
        ))
      }
    }

    return PostgrestFilterBuilder(self)
  }

  /// Perform an UPDATE on the table or view.
  ///
  /// Depending on the column(s) passed to `onConflict`, `.upsert()` allows you to perform the equivalent of `.insert()` if a row with the corresponding `onConflict` columns doesn't exist, or if it does exist, perform an alternative action depending on `ignoreDuplicates`.
  ///
  /// By default, upserted rows are not returned. To return it, chain the call with `.select()`.
  ///
  /// - Parameters:
  ///   - values: The values to upsert with. Pass an object to upsert a single row or an array to upsert multiple rows.
  ///   - onConflict: Comma-separated UNIQUE column(s) to specify how duplicate rows are determined. Two rows are duplicates if all the `onConflict` columns are equal.
  ///   - count: Count algorithm to use to count upserted rows.
  ///   - ignoreDuplicates: If `true`, duplicate rows are ignored. If `false`, duplicate rows are merged with existing rows.
  public func upsert(
    _ values: some Encodable & Sendable,
    onConflict: String? = nil,
    returning: PostgrestReturningOptions = .representation,
    count: CountOption? = nil,
    ignoreDuplicates: Bool = false
  ) throws -> PostgrestFilterBuilder {
    try mutableState.withValue {
      $0.request.method = .post
      var prefersHeaders = [
        "resolution=\(ignoreDuplicates ? "ignore" : "merge")-duplicates",
        "return=\(returning.rawValue)",
      ]
      if let onConflict {
        $0.request.query.appendOrUpdate(URLQueryItem(name: "on_conflict", value: onConflict))
      }
      $0.request.body = try configuration.encoder.encode(values)
      if let count {
        prefersHeaders.append("count=\(count.rawValue)")
      }
      if let prefer = $0.request.headers["Prefer"] {
        prefersHeaders.insert(prefer, at: 0)
      }
      if !prefersHeaders.isEmpty {
        $0.request.headers["Prefer"] = prefersHeaders.joined(separator: ",")
      }

      if let body = $0.request.body,
         let jsonObject = try JSONSerialization.jsonObject(with: body) as? [[String: Any]]
      {
        let allKeys = jsonObject.flatMap(\.keys)
        let uniqueKeys = Set(allKeys).sorted()
        $0.request.query.appendOrUpdate(URLQueryItem(
          name: "columns",
          value: uniqueKeys.joined(separator: ",")
        ))
      }
    }
    return PostgrestFilterBuilder(self)
  }

  /// Perform an UPDATE on the table or view.
  ///
  /// By default, updated rows are not returned. To return it, chain the call with `.select()` after filters.
  ///
  /// - Parameters:
  ///   - values: The values to update with.
  ///   - count: Count algorithm to use to count rows in a table.
  public func update(
    _ values: some Encodable & Sendable,
    returning: PostgrestReturningOptions = .representation,
    count: CountOption? = nil
  ) throws -> PostgrestFilterBuilder {
    try mutableState.withValue {
      $0.request.method = .patch
      var preferHeaders = ["return=\(returning.rawValue)"]
      $0.request.body = try configuration.encoder.encode(values)
      if let count {
        preferHeaders.append("count=\(count.rawValue)")
      }
      if let prefer = $0.request.headers["Prefer"] {
        preferHeaders.insert(prefer, at: 0)
      }
      if !preferHeaders.isEmpty {
        $0.request.headers["Prefer"] = preferHeaders.joined(separator: ",")
      }
    }
    return PostgrestFilterBuilder(self)
  }

  /// Perform a DELETE on the table or view.
  ///
  /// By default, deleted rows are not returned. To return it, chain the call with `.select()` after filters.
  ///
  /// - Parameters:
  ///   - count: Count algorithm to use to count deleted rows.
  public func delete(
    returning: PostgrestReturningOptions = .representation,
    count: CountOption? = nil
  ) -> PostgrestFilterBuilder {
    mutableState.withValue {
      $0.request.method = .delete
      var preferHeaders = ["return=\(returning.rawValue)"]
      if let count {
        preferHeaders.append("count=\(count.rawValue)")
      }
      if let prefer = $0.request.headers["Prefer"] {
        preferHeaders.insert(prefer, at: 0)
      }
      if !preferHeaders.isEmpty {
        $0.request.headers["Prefer"] = preferHeaders.joined(separator: ",")
      }
    }
    return PostgrestFilterBuilder(self)
  }
}
