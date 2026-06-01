//
//  Filter.swift
//  _Realtime
//
//  Created by Guilherme Souza on 24/04/25.
//

public struct Filter<T: RealtimeTable>: Sendable {
  public let wireValue: String

  public static func eq<V: RealtimeFilterValue>(_ kp: KeyPath<T, V>, _ v: V) -> Filter<T> {
    Filter(wireValue: "\(T.columnName(for: kp))=eq.\(v.filterString)")
  }

  public static func neq<V: RealtimeFilterValue>(_ kp: KeyPath<T, V>, _ v: V) -> Filter<T> {
    Filter(wireValue: "\(T.columnName(for: kp))=neq.\(v.filterString)")
  }

  public static func gt<V: RealtimeFilterValue>(_ kp: KeyPath<T, V>, _ v: V) -> Filter<T> {
    Filter(wireValue: "\(T.columnName(for: kp))=gt.\(v.filterString)")
  }

  public static func gte<V: RealtimeFilterValue>(_ kp: KeyPath<T, V>, _ v: V) -> Filter<T> {
    Filter(wireValue: "\(T.columnName(for: kp))=gte.\(v.filterString)")
  }

  public static func lt<V: RealtimeFilterValue>(_ kp: KeyPath<T, V>, _ v: V) -> Filter<T> {
    Filter(wireValue: "\(T.columnName(for: kp))=lt.\(v.filterString)")
  }

  public static func lte<V: RealtimeFilterValue>(_ kp: KeyPath<T, V>, _ v: V) -> Filter<T> {
    Filter(wireValue: "\(T.columnName(for: kp))=lte.\(v.filterString)")
  }

  public static func `in`<V: RealtimeFilterValue>(_ kp: KeyPath<T, V>, _ values: [V]) -> Filter<T>
  {
    let list = values.map(\.filterString).joined(separator: ",")
    return Filter(wireValue: "\(T.columnName(for: kp))=in.(\(list))")
  }
}

public struct UntypedFilter: Sendable {
  public let wireValue: String

  public static func eq(_ column: String, _ value: some RealtimeFilterValue) -> UntypedFilter {
    UntypedFilter(wireValue: "\(column)=eq.\(value.filterString)")
  }

  public static func neq(_ column: String, _ value: some RealtimeFilterValue) -> UntypedFilter {
    UntypedFilter(wireValue: "\(column)=neq.\(value.filterString)")
  }

  public static func gt(_ column: String, _ value: some RealtimeFilterValue) -> UntypedFilter {
    UntypedFilter(wireValue: "\(column)=gt.\(value.filterString)")
  }

  public static func gte(_ column: String, _ value: some RealtimeFilterValue) -> UntypedFilter {
    UntypedFilter(wireValue: "\(column)=gte.\(value.filterString)")
  }

  public static func lt(_ column: String, _ value: some RealtimeFilterValue) -> UntypedFilter {
    UntypedFilter(wireValue: "\(column)=lt.\(value.filterString)")
  }

  public static func lte(_ column: String, _ value: some RealtimeFilterValue) -> UntypedFilter {
    UntypedFilter(wireValue: "\(column)=lte.\(value.filterString)")
  }

  public static func `in`(_ column: String, _ values: [some RealtimeFilterValue]) -> UntypedFilter
  {
    let list = values.map(\.filterString).joined(separator: ",")
    return UntypedFilter(wireValue: "\(column)=in.(\(list))")
  }
}
