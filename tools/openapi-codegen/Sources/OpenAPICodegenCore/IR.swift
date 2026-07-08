//
//  IR.swift
//

/// Intermediate representation of an OpenAPI document, decoupled from
/// OpenAPIKit's types so the emitter doesn't need to know anything about
/// OpenAPI parsing.
struct IRDocument: Equatable {
  var schemas: [IRSchema]
  var operations: [IROperation]
}

struct IRSchema: Equatable {
  var name: String
  var kind: IRSchemaKind
}

enum IRSchemaKind: Equatable {
  case object(properties: [IRProperty])
  case stringEnum(cases: [String])
}

struct IRProperty: Equatable {
  var name: String
  var type: IRType
  var isOptional: Bool
}

indirect enum IRType: Equatable {
  case string
  case integer
  case number
  case boolean
  case array(IRType)
  case schemaRef(String)
  /// An object with no defined properties (OpenAPI's `{"type": "object"}` with
  /// no `properties`) — modeled as `[String: JSONValue]` in emitted Swift.
  case freeform
}

enum IRHTTPMethod: String, Equatable {
  case get, put, post, delete, options, head, patch, trace
}

enum IRParameterLocation: Equatable {
  case path, query, header
}

struct IRParameter: Equatable {
  var name: String
  var location: IRParameterLocation
  var type: IRType
  var isOptional: Bool
}

enum IRRequestBody: Equatable {
  case json(IRType)
  case multipart(fields: [IRMultipartField])
}

struct IRMultipartField: Equatable {
  var name: String
  var type: IRType
  var isFile: Bool
}

enum IRResponseBody: Equatable {
  case none
  case json(IRType)
  case binary
}

struct IRResponse: Equatable {
  var statusCode: Int
  var isError: Bool
  var body: IRResponseBody
}

struct IROperation: Equatable {
  var operationId: String
  var method: IRHTTPMethod
  var path: String
  var parameters: [IRParameter]
  var requestBody: IRRequestBody?
  var responses: [IRResponse]
}
