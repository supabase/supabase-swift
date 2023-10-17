public class PostgrestTransformBuilder: PostgrestBuilder {
  /// Performs a vertical filtering with SELECT.
  /// - Parameters:
  ///   - columns: The columns to retrieve, separated by commas.
  public func select(columns: String = "*") -> PostgrestTransformBuilder {
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
    return self
  }

  /// Orders the result with the specified `column`.
  /// - Parameters:
  ///   - column: The column to order on.
  ///   - ascending: If `true`, the result will be in ascending order.
  ///   - nullsFirst: If `true`, `null`s appear first.
  ///   - foreignTable: The foreign table to use (if `column` is a foreign column).
  public func order(
    column: String,
    ascending: Bool = true,
    nullsFirst: Bool = false,
    foreignTable: String? = nil
  ) -> PostgrestTransformBuilder {
    let key = foreignTable.map { "\($0).order" } ?? "order"
    let existingOrderIndex = queryParams.firstIndex(where: { $0.name == key })
    let value = "\(column).\(ascending ? "asc" : "desc").\(nullsFirst ? "nullsfirst" : "nullslast")"

    if let existingOrderIndex = existingOrderIndex,
      let currentValue = queryParams[existingOrderIndex].value
    {
      queryParams[existingOrderIndex] = (key, "\(currentValue),\(value)")
    } else {
      queryParams.append((key, value))
    }

    return self
  }

  /// Limits the result with the specified `count`.
  /// - Parameters:
  ///   - count: The maximum no. of rows to limit to.
  ///   - foreignTable: The foreign table to use (for foreign columns).
  public func limit(count: Int, foreignTable: String? = nil) -> PostgrestTransformBuilder {
    let key = foreignTable.map { "\($0).limit" } ?? "limit"
    if let index = queryParams.firstIndex(where: { $0.name == key }) {
      queryParams[index] = (key, "\(count)")
    } else {
      queryParams.append((key, "\(count)"))
    }
    return self
  }

  /// Limits the result to rows within the specified range, inclusive.
  /// - Parameters:
  ///   - lowerBounds: The starting index from which to limit the result, inclusive.
  ///   - upperBounds: The last index to which to limit the result, inclusve.
  ///   - foreignTable: The foreign table to use (for foreign columns).
  public func range(
    from lowerBounds: Int,
    to upperBounds: Int,
    foreignTable: String? = nil
  ) -> PostgrestTransformBuilder {
    let keyOffset = foreignTable.map { "\($0).offset" } ?? "offset"
    let keyLimit = foreignTable.map { "\($0).limit" } ?? "limit"

    if let index = queryParams.firstIndex(where: { $0.name == keyOffset }) {
      queryParams[index] = (keyOffset, "\(lowerBounds)")
    } else {
      queryParams.append((keyOffset, "\(lowerBounds)"))
    }

    // Range is inclusive, so add 1
    if let index = queryParams.firstIndex(where: { $0.name == keyLimit }) {
      queryParams[index] = (keyLimit, "\(upperBounds - lowerBounds + 1)")
    } else {
      queryParams.append((keyLimit, "\(upperBounds - lowerBounds + 1)"))
    }

    return self
  }

  /// Retrieves only one row from the result. Result must be one row (e.g. using `limit`), otherwise
  /// this will result in an error.
  public func single() -> PostgrestTransformBuilder {
    headers["Accept"] = "application/vnd.pgrst.object+json"
    return self
  }

  /// Set the response type to CSV.
  public func csv() -> PostgrestTransformBuilder {
    headers["Accept"] = "text/csv"
    return self
  }
}
