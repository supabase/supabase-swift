public struct SortBy {
  public var column: String?
  public var order: String?

  public init(column: String? = nil, order: String? = nil) {
    self.column = column
    self.order = order
  }
}
