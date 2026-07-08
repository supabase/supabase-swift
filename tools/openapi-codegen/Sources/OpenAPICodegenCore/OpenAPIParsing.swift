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

  static func parseNamedSchema(name: String, schema: JSONSchema) throws -> [IRSchema] {
    if case .string = schema.value, let allowedValues = schema.allowedValues {
      let cases = allowedValues.compactMap { $0.value as? String }
      return [IRSchema(name: name, kind: .stringEnum(cases: cases))]
    }
    guard case .object(_, let objectContext) = schema.value else {
      throw UnsupportedSpecConstruct(
        location: "components.schemas.\(name)",
        reason: "top-level schema must be an object or a string enum"
      )
    }
    let (properties, hoisted) = try parseObjectProperties(
      name: name, objectContext: objectContext, location: name)
    return [IRSchema(name: name, kind: .object(properties: properties))] + hoisted
  }

  /// Parses an object schema's properties, hoisting any inline enum or
  /// inline object-with-properties into its own named schema (recursively)
  /// instead of failing. Unlike a union, there's no ambiguity in what Swift
  /// type these become, so a name of `"\(name)_\(propertyName)"` is enough.
  private static func parseObjectProperties(
    name: String,
    objectContext: JSONSchema.ObjectContext,
    location: String
  ) throws -> (properties: [IRProperty], hoisted: [IRSchema]) {
    var properties: [IRProperty] = []
    var hoisted: [IRSchema] = []
    for (propertyName, propertySchema) in objectContext.properties {
      let propertyLocation = "\(location).\(propertyName)"
      let isOptional = !propertySchema.required || propertySchema.nullable

      if case .string = propertySchema.value, let allowedValues = propertySchema.allowedValues {
        let hoistedName = "\(name)_\(propertyName)"
        let cases = allowedValues.compactMap { $0.value as? String }
        hoisted.append(IRSchema(name: hoistedName, kind: .stringEnum(cases: cases)))
        properties.append(
          IRProperty(name: propertyName, type: .schemaRef(hoistedName), isOptional: isOptional))
        continue
      }

      if case .object(_, let nestedContext) = propertySchema.value,
        !nestedContext.properties.isEmpty
      {
        let hoistedName = "\(name)_\(propertyName)"
        let (nestedProperties, nestedHoisted) = try parseObjectProperties(
          name: hoistedName, objectContext: nestedContext, location: propertyLocation)
        hoisted.append(IRSchema(name: hoistedName, kind: .object(properties: nestedProperties)))
        hoisted.append(contentsOf: nestedHoisted)
        properties.append(
          IRProperty(name: propertyName, type: .schemaRef(hoistedName), isOptional: isOptional))
        continue
      }

      properties.append(
        IRProperty(
          name: propertyName,
          type: try parseType(propertySchema, location: propertyLocation),
          isOptional: isOptional
        )
      )
    }
    return (properties, hoisted)
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
  ) throws -> (body: IRRequestBody, hoisted: [IRSchema]) {
    guard let request = either.requestValue else {
      throw UnsupportedSpecConstruct(location: location, reason: "external request body reference")
    }
    if let jsonContent = request.content.first(where: {
      $0.key.typeAndSubtype == "application/json"
    })?.value {
      guard let schemaEither = jsonContent.schema else {
        throw UnsupportedSpecConstruct(
          location: location, reason: "JSON request body without a schema")
      }
      if case .b(let inlineSchema) = schemaEither,
        case .object(_, let objectContext) = inlineSchema.value,
        !objectContext.properties.isEmpty
      {
        let hoistedName = "\(location)_requestBody"
        let (properties, nestedHoisted) = try parseObjectProperties(
          name: hoistedName, objectContext: objectContext, location: hoistedName)
        let hoisted =
          [IRSchema(name: hoistedName, kind: .object(properties: properties))] + nestedHoisted
        return (.json(.schemaRef(hoistedName)), hoisted)
      }
      return (.json(try resolveSchema(schemaEither, location: location)), [])
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
      return (.multipart(fields: fields), [])
    }
    let contentTypes = request.content.keys.map(\.rawValue).joined(separator: ", ")
    throw UnsupportedSpecConstruct(
      location: location, reason: "unsupported request body content type(s): \(contentTypes)")
  }

  // MARK: - Responses

  static func parseResponses(
    _ responses: OpenAPI.Response.Map,
    location: String
  ) throws -> (responses: [IRResponse], hoisted: [IRSchema]) {
    var results: [IRResponse] = []
    var hoisted: [IRSchema] = []
    for (statusCode, responseEither) in responses {
      guard case .status(let code) = statusCode.value else {
        // `default` and range ("4XX") responses aren't modeled in v1; skip them.
        continue
      }
      guard let response = responseEither.responseValue else {
        throw UnsupportedSpecConstruct(
          location: location, reason: "external response reference for status \(code)")
      }
      let (body, bodyHoisted) = try parseResponseBody(
        response.content, location: "\(location) -> \(code)")
      hoisted.append(contentsOf: bodyHoisted)
      results.append(IRResponse(statusCode: code, isError: !statusCode.isSuccess, body: body))
    }
    return (results.sorted { $0.statusCode < $1.statusCode }, hoisted)
  }

  static func parseResponseBody(
    _ content: OpenAPI.Content.Map,
    location: String
  ) throws -> (body: IRResponseBody, hoisted: [IRSchema]) {
    if let jsonContent = content.first(where: { $0.key.typeAndSubtype == "application/json" })?
      .value
    {
      guard let schemaEither = jsonContent.schema else { return (.none, []) }
      if case .b(let inlineSchema) = schemaEither,
        case .object(_, let objectContext) = inlineSchema.value,
        !objectContext.properties.isEmpty
      {
        let hoistedName = "\(location)_response"
        let (properties, nestedHoisted) = try parseObjectProperties(
          name: hoistedName, objectContext: objectContext, location: hoistedName)
        let hoisted =
          [IRSchema(name: hoistedName, kind: .object(properties: properties))] + nestedHoisted
        return (.json(.schemaRef(hoistedName)), hoisted)
      }
      return (.json(try resolveSchema(schemaEither, location: location)), [])
    }
    return (content.isEmpty ? .none : .binary, [])
  }

  // MARK: - Operations

  static func parseOperations(_ document: OpenAPI.Document) throws -> (
    operations: [IROperation], hoisted: [IRSchema]
  ) {
    var operations: [IROperation] = []
    var hoisted: [IRSchema] = []
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
        var requestBody: IRRequestBody?
        if let requestBodyEither = operation.requestBody {
          let (body, bodyHoisted) = try parseRequestBody(requestBodyEither, location: operationId)
          requestBody = body
          hoisted.append(contentsOf: bodyHoisted)
        }
        let (responses, responsesHoisted) = try parseResponses(
          operation.responses, location: operationId)
        hoisted.append(contentsOf: responsesHoisted)
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
    return (operations.sorted { $0.operationId < $1.operationId }, hoisted)
  }

  // MARK: - Document

  public static func parseDocument(_ document: OpenAPI.Document) throws -> IRDocument {
    var schemas: [IRSchema] = []
    for (key, schema) in document.components.schemas {
      schemas.append(contentsOf: try parseNamedSchema(name: key.rawValue, schema: schema))
    }
    let (operations, operationHoisted) = try parseOperations(document)
    schemas.append(contentsOf: operationHoisted)
    return IRDocument(schemas: schemas.sorted { $0.name < $1.name }, operations: operations)
  }
}
