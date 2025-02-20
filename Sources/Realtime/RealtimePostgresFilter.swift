//
//  RealtimePostgresFilter.swift
//  Supabase
//
//  Created by Lucas Abijmil on 19/02/2025.
//

/// A filter that can be used in Realtime.
public enum RealtimePostgresFilter {
  case eq(_ column: String, value: any RealtimePostgresFilterValue)
  case neq(_ column: String, value: any RealtimePostgresFilterValue)
  case gt(_ column: String, value: any RealtimePostgresFilterValue)
  case gte(_ column: String, value: any RealtimePostgresFilterValue)
  case lt(_ column: String, value: any RealtimePostgresFilterValue)
  case lte(_ column: String, value: any RealtimePostgresFilterValue)
  case `in`(_ column: String, values: [any RealtimePostgresFilterValue])

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
