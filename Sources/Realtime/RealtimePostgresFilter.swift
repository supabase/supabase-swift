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
    case .eq(let column, let value):
      return "\(column)=eq.\(value.rawValue)"
    case .neq(let column, let value):
      return "\(column)=neq.\(value.rawValue)"
    case .gt(let column, let value):
      return "\(column)=gt.\(value.rawValue)"
    case .gte(let column, let value):
      return "\(column)=gte.\(value.rawValue)"
    case .lt(let column, let value):
      return "\(column)=lt.\(value.rawValue)"
    case .lte(let column, let value):
      return "\(column)=lte.\(value.rawValue)"
    case .in(let column, let values):
      return "\(column)=in.(\(values.map(\.rawValue).joined(separator: ",")))"
    }
  }
}
