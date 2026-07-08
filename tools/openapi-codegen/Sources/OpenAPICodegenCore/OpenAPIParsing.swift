//
//  OpenAPIParsing.swift
//

import OpenAPIKit30

/// Thrown when the input spec uses a construct this generator deliberately
/// doesn't support (see the plan's Global Constraints for the full list).
/// Never guess at an unfamiliar shape — fail with the exact location instead.
struct UnsupportedSpecConstruct: Error, CustomStringConvertible, Equatable {
  var location: String
  var reason: String

  var description: String { "Unsupported OpenAPI construct at \(location): \(reason)" }
}

public enum OpenAPIParsing {

  // MARK: - Schemas

  static func parseNamedSchema(name: String, schema: JSONSchema) throws -> IRSchema {
    if case .string = schema.value, let allowedValues = schema.allowedValues {
      let cases = allowedValues.compactMap { $0.value as? String }
      return IRSchema(name: name, kind: .stringEnum(cases: cases))
    }
    guard case .object(_, let objectContext) = schema.value else {
      throw UnsupportedSpecConstruct(
        location: "components.schemas.\(name)",
        reason: "top-level schema must be an object or a string enum"
      )
    }
    var properties: [IRProperty] = []
    for (propertyName, propertySchema) in objectContext.properties {
      properties.append(
        IRProperty(
          name: propertyName,
          type: try parseType(propertySchema, location: "\(name).\(propertyName)"),
          isOptional: !propertySchema.required || propertySchema.nullable
        )
      )
    }
    return IRSchema(name: name, kind: .object(properties: properties))
  }

  static func parseType(_ schema: JSONSchema, location: String) throws -> IRType {
    if case .string = schema.value, schema.allowedValues != nil {
      throw UnsupportedSpecConstruct(
        location: location,
        reason: "inline enum; register it as a named component schema instead"
      )
    }
    switch schema.value {
    case .string:
      return .string
    case .integer:
      return .integer
    case .number:
      return .number
    case .boolean:
      return .boolean
    case .array(_, let arrayContext):
      guard let items = arrayContext.items else {
        throw UnsupportedSpecConstruct(location: location, reason: "array schema without 'items'")
      }
      return .array(try parseType(items, location: location + "[]"))
    case .object(_, let objectContext) where objectContext.properties.isEmpty:
      return .freeform
    case .reference(let reference, _):
      guard let name = reference.name else {
        throw UnsupportedSpecConstruct(
          location: location, reason: "external reference without a resolvable name")
      }
      return .schemaRef(name)
    default:
      throw UnsupportedSpecConstruct(location: location, reason: "unsupported schema shape")
    }
  }

  // MARK: - Parameters

  static func parseParameter(
    _ either: Either<JSONReference<OpenAPI.Parameter>, OpenAPI.Parameter>,
    location: String
  ) throws -> IRParameter {
    guard let parameter = either.parameterValue else {
      throw UnsupportedSpecConstruct(location: location, reason: "external parameter reference")
    }
    let parameterLocation = "\(location).\(parameter.name)"
    let irLocation: IRParameterLocation
    switch parameter.location {
    case .path: irLocation = .path
    case .query: irLocation = .query
    case .header: irLocation = .header
    case .cookie:
      throw UnsupportedSpecConstruct(
        location: parameterLocation, reason: "cookie parameters aren't supported")
    }
    guard let schema = parameter.schemaOrContent.schemaValue else {
      throw UnsupportedSpecConstruct(
        location: parameterLocation, reason: "parameter uses 'content' instead of 'schema'")
    }
    return IRParameter(
      name: parameter.name,
      location: irLocation,
      type: try parseType(schema, location: parameterLocation),
      isOptional: !parameter.required || schema.nullable
    )
  }

  // MARK: - Schema references in content bodies

  static func resolveSchema(
    _ either: Either<JSONReference<JSONSchema>, JSONSchema>,
    location: String
  ) throws -> IRType {
    switch either {
    case .a(let reference):
      guard let name = reference.name else {
        throw UnsupportedSpecConstruct(
          location: location, reason: "external schema reference without a resolvable name")
      }
      return .schemaRef(name)
    case .b(let schema):
      return try parseType(schema, location: location)
    }
  }

  // MARK: - Request bodies

  static func parseRequestBody(
    _ either: Either<JSONReference<OpenAPI.Request>, OpenAPI.Request>,
    location: String
  ) throws -> IRRequestBody {
    guard let request = either.requestValue else {
      throw UnsupportedSpecConstruct(location: location, reason: "external request body reference")
    }
    if let jsonContent = request.content.first(where: {
      $0.key.typeAndSubtype == "application/json"
    })?.value {
      guard let schema = jsonContent.schema else {
        throw UnsupportedSpecConstruct(
          location: location, reason: "JSON request body without a schema")
      }
      return .json(try resolveSchema(schema, location: location))
    }
    if let multipartContent = request.content.first(where: {
      $0.key.typeAndSubtype == "multipart/form-data"
    })?.value {
      guard let schemaEither = multipartContent.schema, case .b(let objectSchema) = schemaEither,
        case .object(_, let objectContext) = objectSchema.value
      else {
        throw UnsupportedSpecConstruct(
          location: location, reason: "multipart request body must be an inline object schema")
      }
      var fields: [IRMultipartField] = []
      for (fieldName, fieldSchema) in objectContext.properties {
        var isFile = false
        if case .string(let core, _) = fieldSchema.value, core.format == .binary {
          isFile = true
        }
        fields.append(
          IRMultipartField(
            name: fieldName,
            type: try parseType(fieldSchema, location: "\(location).\(fieldName)"),
            isFile: isFile
          )
        )
      }
      return .multipart(fields: fields)
    }
    let contentTypes = request.content.keys.map(\.rawValue).joined(separator: ", ")
    throw UnsupportedSpecConstruct(
      location: location, reason: "unsupported request body content type(s): \(contentTypes)")
  }

  // MARK: - Responses

  static func parseResponses(
    _ responses: OpenAPI.Response.Map,
    location: String
  ) throws -> [IRResponse] {
    var results: [IRResponse] = []
    for (statusCode, responseEither) in responses {
      guard case .status(let code) = statusCode.value else {
        // `default` and range ("4XX") responses aren't modeled in v1; skip them.
        continue
      }
      guard let response = responseEither.responseValue else {
        throw UnsupportedSpecConstruct(
          location: location, reason: "external response reference for status \(code)")
      }
      let body = try parseResponseBody(response.content, location: "\(location) -> \(code)")
      results.append(IRResponse(statusCode: code, isError: !statusCode.isSuccess, body: body))
    }
    return results.sorted { $0.statusCode < $1.statusCode }
  }

  static func parseResponseBody(
    _ content: OpenAPI.Content.Map,
    location: String
  ) throws -> IRResponseBody {
    if let jsonContent = content.first(where: { $0.key.typeAndSubtype == "application/json" })?
      .value
    {
      guard let schema = jsonContent.schema else { return .none }
      return .json(try resolveSchema(schema, location: location))
    }
    return content.isEmpty ? .none : .binary
  }

  // MARK: - Operations

  static func parseOperations(_ document: OpenAPI.Document) throws -> [IROperation] {
    var operations: [IROperation] = []
    for (path, pathItemEither) in document.paths {
      guard let pathItem = pathItemEither.pathItemValue else {
        throw UnsupportedSpecConstruct(
          location: path.rawValue, reason: "external path item reference")
      }
      let methodOperations: [(IRHTTPMethod, OpenAPI.Operation?)] = [
        (.get, pathItem.get),
        (.put, pathItem.put),
        (.post, pathItem.post),
        (.delete, pathItem.delete),
        (.options, pathItem.options),
        (.head, pathItem.head),
        (.patch, pathItem.patch),
        (.trace, pathItem.trace),
      ]
      for (method, maybeOperation) in methodOperations {
        guard let operation = maybeOperation else { continue }
        let operationLocation = "\(method.rawValue.uppercased()) \(path.rawValue)"
        guard let operationId = operation.operationId else {
          throw UnsupportedSpecConstruct(location: operationLocation, reason: "missing operationId")
        }
        var parameters: [IRParameter] = []
        for parameterEither in pathItem.parameters + operation.parameters {
          parameters.append(try parseParameter(parameterEither, location: operationId))
        }
        let requestBody = try operation.requestBody.map {
          try parseRequestBody($0, location: operationId)
        }
        let responses = try parseResponses(operation.responses, location: operationId)
        operations.append(
          IROperation(
            operationId: operationId,
            method: method,
            path: path.rawValue,
            parameters: parameters,
            requestBody: requestBody,
            responses: responses
          )
        )
      }
    }
    return operations.sorted { $0.operationId < $1.operationId }
  }

  // MARK: - Document

  public static func parseDocument(_ document: OpenAPI.Document) throws -> IRDocument {
    var schemas: [IRSchema] = []
    for (key, schema) in document.components.schemas {
      schemas.append(try parseNamedSchema(name: key.rawValue, schema: schema))
    }
    return IRDocument(
      schemas: schemas.sorted { $0.name < $1.name },
      operations: try parseOperations(document)
    )
  }
}
