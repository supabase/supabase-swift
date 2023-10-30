import Foundation

public final class PostgrestQueryBuilder: PostgrestBuilder {
  /// Performs a vertical filtering with SELECT.
  /// - Parameters:
  ///   - columns: The columns to retrieve, separated by commas.
  ///   - head: When set to true, select will void data.
  ///   - count: Count algorithm to use to count rows in a table.
  /// - Returns: A `PostgrestFilterBuilder` instance for further filtering or operations.
  public func select(
    columns: String = "*",
    head: Bool = false,
    count: CountOption? = nil
  ) -> PostgrestFilterBuilder {
    method = "GET"
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
    appendSearchParams(name: "select", value: cleanedColumns)
    if let count {
      headers["Prefer"] = "count=\(count.rawValue)"
    }
    if head {
      method = "HEAD"
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
    values: some Encodable,
    returning: PostgrestReturningOptions? = nil,
    count: CountOption? = nil
  ) throws -> PostgrestFilterBuilder {
    method = "POST"
    var prefersHeaders: [String] = []
    if let returning {
      prefersHeaders.append("return=\(returning.rawValue)")
    }
    body = try configuration.encoder.encode(values)
    if let count {
      prefersHeaders.append("count=\(count.rawValue)")
    }
    if let prefer = headers["Prefer"] {
      prefersHeaders.insert(prefer, at: 0)
    }
    if !prefersHeaders.isEmpty {
      headers["Prefer"] = prefersHeaders.joined(separator: ",")
    }

    // TODO: How to do this in Swift?
    // if (Array.isArray(values)) {
    //     const columns = values.reduce((acc, x) => acc.concat(Object.keys(x)), [] as string[])
    //     if (columns.length > 0) {
    //         const uniqueColumns = [...new Set(columns)].map((column) => `"${column}"`)
    //         this.url.searchParams.set('columns', uniqueColumns.join(','))
    //     }
    // }

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
    values: some Encodable,
    onConflict: String? = nil,
    returning: PostgrestReturningOptions = .representation,
    count: CountOption? = nil,
    ignoreDuplicates: Bool = false
  ) throws -> PostgrestFilterBuilder {
    method = "POST"
    var prefersHeaders = [
      "resolution=\(ignoreDuplicates ? "ignore" : "merge")-duplicates",
      "return=\(returning.rawValue)",
    ]
    if let onConflict {
      appendSearchParams(name: "on_conflict", value: onConflict)
    }
    body = try configuration.encoder.encode(values)
    if let count {
      prefersHeaders.append("count=\(count.rawValue)")
    }
    if let prefer = headers["Prefer"] {
      prefersHeaders.insert(prefer, at: 0)
    }
    if !prefersHeaders.isEmpty {
      headers["Prefer"] = prefersHeaders.joined(separator: ",")
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
    values: some Encodable,
    returning: PostgrestReturningOptions = .representation,
    count: CountOption? = nil
  ) throws -> PostgrestFilterBuilder {
    method = "PATCH"
    var preferHeaders = ["return=\(returning.rawValue)"]
    body = try configuration.encoder.encode(values)
    if let count {
      preferHeaders.append("count=\(count.rawValue)")
    }
    if let prefer = headers["Prefer"] {
      preferHeaders.insert(prefer, at: 0)
    }
    if !preferHeaders.isEmpty {
      headers["Prefer"] = preferHeaders.joined(separator: ",")
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
    method = "DELETE"
    var preferHeaders = ["return=\(returning.rawValue)"]
    if let count {
      preferHeaders.append("count=\(count.rawValue)")
    }
    if let prefer = headers["Prefer"] {
      preferHeaders.insert(prefer, at: 0)
    }
    if !preferHeaders.isEmpty {
      headers["Prefer"] = preferHeaders.joined(separator: ",")
    }
    return PostgrestFilterBuilder(self)
  }
}
