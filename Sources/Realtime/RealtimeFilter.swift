public enum RealtimeFilter {
  case eq(_ column: String, value: any RealtimeFilterValue)
  case neq(_ column: String, value: any RealtimeFilterValue)
  case gt(_ column: String, value: any RealtimeFilterValue)
  case gte(_ column: String, value: any RealtimeFilterValue)
  case lt(_ column: String, value: any RealtimeFilterValue)
  case lte(_ column: String, value: any RealtimeFilterValue)
  case `in`(_ column: String, values: [any RealtimeFilterValue])

  var value: String {
    switch self {
    case let .eq(column, value):
      return "\(column)=eq.\(value.rawValue)"
    case let .neq(column, value):
      return "\(column)=neq.\(value.rawValue)"
    case let .gt(column, value):
      return "\(column)=gt.\(value.rawValue)"
    case let .gte(column, value):
      return "\(column)=gte.\(value.rawValue)"
    case let .lt(column, value):
      return "\(column)=lt.\(value.rawValue)"
    case let .lte(column, value):
      return "\(column)=lte.\(value.rawValue)"
    case let .in(column, values):
      return "\(column)=in.(\(values.map(\.rawValue)))"
    }
  }
}