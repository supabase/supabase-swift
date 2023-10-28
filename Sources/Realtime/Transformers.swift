//
//  File.swift
//  
//
//  Created by Guilherme Souza on 28/10/23.
//

import Foundation

enum PostgresTypes: String, CaseIterable {
  case abstime
  case bool
  case date
  case daterange
  case float4
  case float8
  case int2
  case int4
  case int4range
  case int8
  case int8range
  case json
  case jsonb
  case money
  case numeric
  case oid
  case reltime
  case time
  case text
  case timestamp
  case timestamptz
  case timetz
  case tsrange
  case tstzrange
}

struct PostgresColumn {
  let name: String
  let type: String
  let flags: [String]?
  let typeModifier: Int?
}

private func convertChangeData(
  columns: [[String: Any]],
  record: [String: Any],
  skipTypes: [String]? = nil
) -> [String: Any] {
  var result: [String: Any] = [:]
  var parsedColumns: [PostgresColumn] = []

  for element in columns {
    if let name = element["name"] as? String, let type = element["type"] as? String {
      parsedColumns.append(PostgresColumn(name: name, type: type, flags: nil, typeModifier: nil))
    }
  }

  record.forEach { key, value in
    result[key] = convertColumn(columnName: key, columns: parsedColumns, record: record, skipTypes: skipTypes ?? [])
  }

  return result
}

func convertColumn(
  columnName: String,
  columns: [PostgresColumn],
  record: [String: Any],
  skipTypes: [String]
) -> Any {
  let column = columns.first { $0.name == columnName }
  let columnValue = record[columnName]

  if let column, !skipTypes.contains(column.type) {
    return convertCell(type: column.type, value: columnValue as Any)
  }

  return columnValue as Any
}

func convertCell(type: String, value: Any) -> Any {
  // if data type is an array
  if type.hasPrefix("_") {
    let dataType = type.dropFirst()
    return toArray(value: value, type: String(dataType))
  }

  let typeEnum = PostgresTypes.allCases.first {
    $0.rawValue == type
  }

  switch typeEnum {
  case .bool:
    return toBoolean(value) as Any
  case .float4, .float8, .numeric:
    return toDouble(value) as Any
  case .int2, .int4, .int8, .oid:
    return toInt(value) as Any
  case .json, .jsonb:
    return toJSON(value)
  case .timestamp:
    return toTimestrampString(value) as Any // Format to be consistent with PostgREST
  case .abstime, // To allow users to cast it based on Timezone
      .date, // To allow users to cast it based on Timezone
      .daterange,
      .int4range,
      .int8range,
      .money,
      .reltime, // To allow users to cast it based on Timezone
      .text,
      .time, // To allow users to cast it based on Timezone
      .timestamptz, // To allow users to cast it based on Timezone
      .timetz, // To allow users to cast it based on Timezone
      .tsrange,
      .tstzrange:
    return value
  case .none:
    return value
  }
}

func toArray(value: Any, type: String) -> Any {
  return value
//  guard let value = value as? String else {
//    return value
//  }
//
//  let closeBrace = value.last
//  let openBrace = value.first
//
//  // Confirm value is a Postgres array by checking curly brackets
//  if openBrace == "{" && closeBrace == "}" {
//    let valTrim = value.dropFirst().dropLast()
//    var arr: [Any] = []
//
//    do {
//      let data = Data("[\(valTrim)]".utf8)
//      arr = try JSONSerialization.jsonObject(with: data) as? [Any] ?? []
//    } catch {
//      
//    }
//    return arr.map{(convertCell(type: type, value: <#T##Any#>))}
    // TODO: find a better solution to separate Postgres array data
//    try {
//      arr = json.decode('[$valTrim]') as List;
//    } catch (_) {
      // WARNING: splitting on comma does not cover all edge cases
//      arr = valTrim != '' ? valTrim.split(',') : [];
//    }

//    return arr.map((val) => convertCell(type, val)).toList();
//  }
}

func toBoolean(_ value: Any) -> Bool? {
  if let bool = value as? Bool {
    return bool
  }

  if let string = value as? String {
    if string == "t" || string == "true" {
      return true
    }

    if string == "f" || string == "false" {
      return false
    }
  }

  return nil
}

func toDouble(_ value: Any) -> Double? {
  if let value = value as? Double {
    return value
  }

  let string = String(describing: value)
  return Double(string)
}

func toInt(_ value: Any) -> Int? {
  if let value = value as? Int {
    return value
  }

  let string = String(describing: value)
  return Int(string)
}

func toJSON(_ value: Any) -> Any {
  // TODO: check if we need to handle this some way
  value
}

func toTimestrampString(_ value: Any) -> String? {
  guard let value = value as? String else {
    return nil
  }

  return value.replacingOccurrences(of: " ", with: "T")
}

private func getEnrichedPayload(_ payload: Payload) -> Payload {
  let postgresChanges = payload["data"] as? Payload ?? payload
  let schema = postgresChanges["schema"]
  let table = postgresChanges["table"]
  let commitTimestamp = postgresChanges["commit_timestamp"]
  let type = postgresChanges["type"]
  let errors = postgresChanges["errors"]

  var enrichedPayload = [
    "schema": schema,
    "table": table,
    "commit_timestamp": commitTimestamp,
    "eventType": type,
    "errors": errors
  ].compactMapValues { $0 }

  for (key, value) in getPayloadRecords(postgresChanges) {
    enrichedPayload[key] = value
  }

  return enrichedPayload
}

private func getPayloadRecords(_ payload: Payload) -> [String: [String: Any]] {
  var new: [String: Any] = [:]
  var old: [String: Any] = [:]

  guard let type = payload["type"] as? String else {
    return [:]
  }

  if type == "INSERT" || type == "UPDATE" {
    new = convertChangeData(
      columns: payload["columns"] as? [[String: Any]] ?? [],
      record: payload["record"] as? [String: Any] ?? [:]
    )
  }

  if type == "UPDATE" || type == "DELETE" {
    old = convertChangeData(
      columns: payload["columns"] as? [[String: Any]] ?? [],
      record: payload["old_record"] as? [String: Any] ?? [:]
    )
  }

  return ["new": new, "old": old]
}
