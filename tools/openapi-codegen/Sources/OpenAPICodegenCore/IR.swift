//
//  IR.swift
//

/// Intermediate representation of an OpenAPI document, decoupled from
/// OpenAPIKit's types so the emitter doesn't need to know anything about
/// OpenAPI parsing.
public struct IRDocument: Equatable {
  public var schemas: [IRSchema]
  public var operations: [IROperation]
}

public struct IRSchema: Equatable {
  public var name: String
  public var kind: IRSchemaKind
}

public enum IRSchemaKind: Equatable {
  case object(properties: [IRProperty])
  case stringEnum(cases: [String])
}

public struct IRProperty: Equatable {
  public var name: String
  public var type: IRType
  public var isOptional: Bool
}

public indirect enum IRType: Equatable {
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

public enum IRHTTPMethod: String, Equatable {
  case get, put, post, delete, options, head, patch, trace
}

public enum IRParameterLocation: Equatable {
  case path, query, header
}

public struct IRParameter: Equatable {
  public var name: String
  public var location: IRParameterLocation
  public var type: IRType
  public var isOptional: Bool
}

public enum IRRequestBody: Equatable {
  case json(IRType)
  case multipart(fields: [IRMultipartField])
}

public struct IRMultipartField: Equatable {
  public var name: String
  public var type: IRType
  public var isFile: Bool
}

public enum IRResponseBody: Equatable {
  case none
  case json(IRType)
  case binary
}

public struct IRResponse: Equatable {
  public var statusCode: Int
  public var isError: Bool
  public var body: IRResponseBody
}

public struct IROperation: Equatable {
  public var operationId: String
  public var method: IRHTTPMethod
  public var path: String
  public var parameters: [IRParameter]
  public var requestBody: IRRequestBody?
  public var responses: [IRResponse]
}
