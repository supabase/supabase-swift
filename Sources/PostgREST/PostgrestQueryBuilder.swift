import Foundation
@_spi(Internal) import _Helpers

public final class PostgrestQueryBuilder: PostgrestBuilder {
  /// Performs a vertical filtering with SELECT.
  /// - Parameters:
  ///   - columns: The columns to retrieve, separated by commas.
  ///   - head: When set to true, select will void data.
  ///   - count: Count algorithm to use to count rows in a table.
  /// - Returns: A `PostgrestFilterBuilder` instance for further filtering or operations.
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

      $0.request.query.append(URLQueryItem(name: "select", value: cleanedColumns))

      if let count {
        $0.request.headers["Prefer"] = "count=\(count.rawValue)"
      }
      if head {
        $0.request.method = .head
      }
    }

    return PostgrestFilterBuilder(self)
  }

  /// Performs an INSERT into the table.
  /// - Parameters:
  ///   - values: The values to insert.
  ///   - returning: The returning options for the query.
  ///   - count: Count algorithm to use to count rows in a table.
  /// - Returns: A `PostgrestFilterBuilder` instance for further filtering or operations.
  /// - Throws: An error if the insert fails.
  public func insert(
    _ values: some Encodable,
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
      if let body = $0.request.body, let jsonObject = try JSONSerialization.jsonObject(with: body) as? [[String: Any]] {
        let allKeys = jsonObject.flatMap(\.keys)
        let uniqueKeys = Set(allKeys).sorted()
        $0.request.query.append(URLQueryItem(name: "columns", value: uniqueKeys.joined(separator: ",")))
      }
    }

    return PostgrestFilterBuilder(self)
  }

  /// Performs an UPSERT into the table.
  /// - Parameters:
  ///   - values: The values to insert.
  ///   - onConflict: The column(s) with a unique constraint to perform the UPSERT.
  ///   - returning: The returning options for the query.
  ///   - count: Count algorithm to use to count rows in a table.
  ///   - ignoreDuplicates: Specifies if duplicate rows should be ignored and not inserted.
  /// - Returns: A `PostgrestFilterBuilder` instance for further filtering or operations.
  /// - Throws: An error if the upsert fails.
  public func upsert(
    _ values: some Encodable,
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
        $0.request.query.append(URLQueryItem(name: "on_conflict", value: onConflict))
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

      if let body = $0.request.body, let jsonObject = try JSONSerialization.jsonObject(with: body) as? [[String: Any]] {
        let allKeys = jsonObject.flatMap(\.keys)
        let uniqueKeys = Set(allKeys).sorted()
        $0.request.query.append(URLQueryItem(name: "columns", value: uniqueKeys.joined(separator: ",")))
      }
    }
    return PostgrestFilterBuilder(self)
  }

  /// Performs an UPDATE on the table.
  /// - Parameters:
  ///   - values: The values to update.
  ///   - returning: The returning options for the query.
  ///   - count: Count algorithm to use to count rows in a table.
  /// - Returns: A `PostgrestFilterBuilder` instance for further filtering or operations.
  /// - Throws: An error if the update fails.
  public func update(
    _ values: some Encodable,
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

  /// Performs a DELETE on the table.
  /// - Parameters:
  ///   - returning: The returning options for the query.
  ///   - count: Count algorithm to use to count rows in a table.
  /// - Returns: A `PostgrestFilterBuilder` instance for further filtering or operations.
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
