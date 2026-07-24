import SwiftSyntax

struct StoredPropertyInfo {
  let name: String  // Swift identifier, e.g. "isComplete"
  let typeSyntax: TypeSyntax
  let columnName: String  // PostgREST column, e.g. "is_complete"
  let isPrimaryKey: Bool
  let hasDefault: Bool
  let isRelationship: Bool
  let isOptional: Bool  // whether the Swift type is Optional<T>
}

extension AttributeListSyntax {
  func containsAttribute(named name: String) -> Bool {
    contains {
      $0.as(AttributeSyntax.self)?.attributeName.trimmedDescription == name
    }
  }

  func attribute(named name: String) -> AttributeSyntax? {
    compactMap { $0.as(AttributeSyntax.self) }
      .first { $0.attributeName.trimmedDescription == name }
  }
}

func parseStoredProperties(from decl: StructDeclSyntax) -> [StoredPropertyInfo] {
  var result: [StoredPropertyInfo] = []

  for member in decl.memberBlock.members {
    guard
      let varDecl = member.decl.as(VariableDeclSyntax.self),
      varDecl.bindingSpecifier.tokenKind == .keyword(.var),
      let binding = varDecl.bindings.first,
      let pattern = binding.pattern.as(IdentifierPatternSyntax.self),
      let typeAnnotation = binding.typeAnnotation,
      binding.accessorBlock == nil  // skip computed properties
    else { continue }

    let name = pattern.identifier.text
    let typeSyntax = typeAnnotation.type
    let typeText = typeSyntax.trimmedDescription
    let isOptional =
      typeSyntax.is(OptionalTypeSyntax.self)
      || typeText.hasSuffix("?")

    let attrs = varDecl.attributes

    let isPrimaryKey = attrs.containsAttribute(named: "PrimaryKey")
    let hasDefault = attrs.containsAttribute(named: "Default")
    let isRelationship = attrs.containsAttribute(named: "Relationship")

    // Resolve column name: @Column override takes precedence, otherwise snake_case
    let columnName: String
    if let colAttr = attrs.attribute(named: "Column"),
      let args = colAttr.arguments?.as(LabeledExprListSyntax.self),
      let first = args.first,
      let strLit = first.expression.as(StringLiteralExprSyntax.self),
      let segments = strLit.segments.first?.as(StringSegmentSyntax.self)
    {
      columnName = segments.content.text
    } else {
      columnName = camelToSnake(name)
    }

    result.append(
      StoredPropertyInfo(
        name: name,
        typeSyntax: typeSyntax,
        columnName: columnName,
        isPrimaryKey: isPrimaryKey,
        hasDefault: hasDefault,
        isRelationship: isRelationship,
        isOptional: isOptional
      ))
  }

  return result
}
