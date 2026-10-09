//
//  Diagnostics.swift
//  PostgrestMacrosPlugin
//
//  Created by Guilherme Souza on 21/08/26.
//

import SwiftDiagnostics
import SwiftSyntax
import SwiftSyntaxMacros

/// An error attached to a specific syntax node.
///
/// Throwing `MacroExpansionErrorMessage` puts the caret on the attribute, which is wrong for a
/// per-property misuse: the reader needs to see the property that caused it.
struct PostgrestDiagnostic: DiagnosticMessage {
  let message: String
  var severity: DiagnosticSeverity { .error }
  var diagnosticID: MessageID { MessageID(domain: "PostgrestMacros", id: message) }
}

extension MacroExpansionContext {
  /// Emits an error pointing at `node`.
  func error(_ message: String, at node: some SyntaxProtocol) {
    diagnose(Diagnostic(node: node, message: PostgrestDiagnostic(message: message)))
  }
}

/// What a `@Relationship` attribute embeds.
enum PostgrestEmbedReference {
  /// `@Relationship(\Comment.todoID)`: the foreign key, rendered as a namespace reference,
  /// `Comment.columns.todoID`.
  case foreignKey(String)

  /// `@Relationship(computed: \Channel.Columns.getMessages)`: the relationship's member name,
  /// `getMessages`. Only the name is kept. The expansion reads it off the selection's own relation,
  /// so a key path rooted on another relation's namespace does not compile.
  case computed(String)
}

/// The `@Relationship` argument, or `nil` if it is not a single-component key path with a written
/// root.
///
/// The root is what makes the reference resolvable from the expansion, and it is why the key path
/// has to be written in full: `\.todoID` infers its root from context the macro cannot see.
///
/// A foreign key is one component, because it is one column; a longer path would name something
/// inside a column's value, which is not a relationship. A computed relationship is parsed as
/// `Channel` followed by `.Columns.getMessages`, so only its last component is read.
func postgrestEmbedReference(_ attribute: AttributeSyntax) -> PostgrestEmbedReference? {
  guard
    let argument = attribute.arguments?.as(LabeledExprListSyntax.self)?.first,
    let keyPath = argument.expression.as(KeyPathExprSyntax.self),
    let root = keyPath.root?.trimmedDescription,
    let property = keyPath.components.last?.component.as(KeyPathPropertyComponentSyntax.self)
  else { return nil }
  let name = property.declName.baseName.trimmedDescription
  switch argument.label?.text {
  case nil where keyPath.components.count == 1: return .foreignKey("\(root).columns.\(name)")
  case "computed": return .computed(name)
  default: return nil
  }
}

/// What an `@Aggregate` attribute selects.
struct PostgrestAggregateReference {
  /// The function's case name, `sum`, which is also the name of the method that applies it.
  var function: String

  /// The column, rendered as a namespace reference, `Order.columns.amount`, or `nil` for
  /// `count()`, which counts rows rather than values of a column.
  var column: String?

  /// The expression the selection emits, `Order.columns.amount.sum()`.
  func expression(relation: String) -> String {
    guard let column else { return "_PostgrestAggregate<\(relation), Int>.countAll" }
    return "\(column).\(function)()"
  }
}

/// The `@Aggregate` arguments, or `nil` if they are not a written `.function` and, unless the
/// function is `.count`, an `of:` key path to one column with a written root.
///
/// The key path names the relation's stored property, not its `Columns` member. An attribute
/// argument is type-checked before `@Table` expands, so `Order.columns.amount` does not resolve
/// there, while `\Order.amount` does — the same reason `@Relationship` takes one.
func postgrestAggregateReference(_ attribute: AttributeSyntax) -> PostgrestAggregateReference? {
  guard
    let arguments = attribute.arguments?.as(LabeledExprListSyntax.self),
    let function = arguments.first?.expression.as(MemberAccessExprSyntax.self)?
      .declName.baseName.text
  else { return nil }
  guard let argument = arguments.dropFirst().first else {
    return function == "count" ? PostgrestAggregateReference(function: function) : nil
  }
  guard
    argument.label?.text == "of",
    let keyPath = argument.expression.as(KeyPathExprSyntax.self),
    keyPath.components.count == 1,
    let root = keyPath.root?.trimmedDescription,
    let property = keyPath.components.first?.component.as(KeyPathPropertyComponentSyntax.self)
  else { return nil }
  let name = property.declName.baseName.trimmedDescription
  return PostgrestAggregateReference(function: function, column: "\(root).columns.\(name)")
}

extension DeclGroupSyntax {
  /// The first `@Relationship` or `@Aggregate` attribute on a stored property, if any.
  ///
  /// Both belong to a selection, never to a relation, so `@Table` rejects them. A relation carries
  /// columns; an embed or an aggregate is declared by the selection that wants it.
  ///
  /// Matching on the attribute *name* rather than resolving the macro is what keeps this working
  /// from `@Table`, which never expands either attribute itself.
  func postgrestSelectionOnlyAttribute() -> AttributeSyntax? {
    for member in memberBlock.members {
      guard let variable = member.decl.as(VariableDeclSyntax.self) else { continue }
      for attribute in variable.attributes.compactMap({ $0.as(AttributeSyntax.self) })
      where ["Relationship", "Aggregate"].contains(attribute.attributeName.trimmedDescription) {
        return attribute
      }
    }
    return nil
  }
}

extension DeclGroupSyntax {
  /// Reports every stored property whose type is left to its initializer.
  ///
  /// `postgrestStoredProperties()` reads syntax, so `var isDone = false` gives it no annotation to
  /// read and the property is dropped from `CodingKeys`, `Columns` and `Draft`.
  /// Nothing about that is loud: the initializer doubles as a decoding default, so the type still
  /// compiles, the column simply never round-trips, and the mistake surfaces only much later, at
  /// some unrelated call site that expected the column to exist. A macro cannot recover the type
  /// from the initializer expression, so the author is asked for an annotation instead.
  ///
  /// The condition is `postgrestType(at:)` returning `nil` — the very test the reader uses to skip
  /// a binding — so the two cannot drift apart. In particular `var draft, review: String` is not
  /// reported: `draft` has no annotation of its own but takes `review`'s, exactly as the reader
  /// resolves it.
  ///
  /// Returns `true` if anything was reported, so the caller can stop before emitting an expansion
  /// that leaves the column out.
  func postgrestDiagnoseUnannotatedProperties(
    macro: String,
    in context: some MacroExpansionContext
  ) -> Bool {
    var reported = false
    for member in memberBlock.members {
      guard
        let variable = member.decl.as(VariableDeclSyntax.self),
        !variable.modifiers.contains(where: { $0.name.text == "static" })
      else { continue }

      let bindings = Array(variable.bindings)
      for index in bindings.indices {
        let binding = bindings[index]
        guard
          let identifier = binding.pattern.as(IdentifierPatternSyntax.self),
          binding.isPostgrestStored,
          bindings.postgrestType(at: index) == nil
        else { continue }

        let name = identifier.identifier.text
        context.error(
          """
          \(macro) requires an explicit type annotation on '\(name)', as in \
          'var \(name): <Type> = ...' — without one the macro cannot infer the type, and the \
          column is dropped
          """,
          at: binding.pattern
        )
        reported = true
      }
    }
    return reported
  }
}

extension DeclGroupSyntax {
  /// Reports a marker attribute whose placement cannot mean what it says.
  ///
  /// Marker attributes sit on the declaration, so every binding of `@Default var a, b: Bool`
  /// carries them, and `@PrimaryKey var a: Int, b: Int` is a compound key. Two placements have no
  /// such reading:
  ///
  /// - `@Column("a") var x: Int, y: Int` names one column for two properties. Left alone, both
  ///   `CodingKeys` cases get the raw value `"a"` and the compiler rejects generated code the
  ///   author never wrote.
  /// - `@PrimaryKey var id: Int?` marks a nullable property as the key, which Postgres never
  ///   allows. Left alone it expands without complaint and nothing downstream notices.
  ///
  /// Returns `true` if anything was reported.
  func postgrestDiagnoseMarkerPlacement(in context: some MacroExpansionContext) -> Bool {
    var reported = false
    for member in memberBlock.members {
      guard
        let variable = member.decl.as(VariableDeclSyntax.self),
        !variable.modifiers.contains(where: { $0.name.text == "static" })
      else { continue }
      let attributes = variable.attributes.compactMap { $0.as(AttributeSyntax.self) }
      func attribute(_ name: String) -> AttributeSyntax? {
        attributes.first { $0.attributeName.trimmedDescription == name }
      }

      if let column = attribute("Column"), variable.bindings.count > 1 {
        context.error(
          """
          @Column names one column, but this declaration binds \(variable.bindings.count) \
          properties — split it into one declaration per property
          """,
          at: column
        )
        reported = true
      }

      guard attribute("PrimaryKey") != nil else { continue }
      let bindings = Array(variable.bindings)
      for index in bindings.indices {
        let binding = bindings[index]
        guard
          let identifier = binding.pattern.as(IdentifierPatternSyntax.self),
          binding.isPostgrestStored,
          let type = bindings.postgrestType(at: index),
          postgrestIsOptionalType(type.trimmedDescription)
        else { continue }
        let name = identifier.identifier.text
        context.error(
          """
          @PrimaryKey on '\(name)' has an Optional type, but a primary key is never null — \
          make '\(name)' non-optional, or move @PrimaryKey to the key column
          """,
          at: binding.pattern
        )
        reported = true
      }
    }
    return reported
  }
}

extension DeclGroupSyntax {
  /// Reports every `@Relationship` whose argument is not a usable foreign key key path.
  ///
  /// Left alone, the property falls through to the plain-column path and the reader gets
  /// "value of type 'Todo.Columns' has no member 'comments'" on a line they did not write — the
  /// column the embed deliberately does not have.
  ///
  /// Returns `true` if anything was reported.
  func postgrestDiagnoseRelationships(in context: some MacroExpansionContext) -> Bool {
    var reported = false
    for member in memberBlock.members {
      guard let variable = member.decl.as(VariableDeclSyntax.self) else { continue }
      for attribute in variable.attributes.compactMap({ $0.as(AttributeSyntax.self) })
      where attribute.attributeName.trimmedDescription == "Relationship"
        && postgrestEmbedReference(attribute) == nil
      {
        context.error(
          """
          @Relationship requires a key path to one foreign key column, written with its root, \
          as in '@Relationship(\\Comment.todoID)', or to a computed relationship, as in \
          '@Relationship(computed: \\Channel.Columns.getMessages)'
          """,
          at: attribute
        )
        reported = true
      }
    }
    return reported
  }
}

extension DeclGroupSyntax {
  /// Reports every `@Aggregate` whose arguments cannot be read, and every property carrying both
  /// `@Aggregate` and `@Relationship`.
  ///
  /// Left alone, the property falls through to the plain-column path and the reader gets "value of
  /// type 'Order.Columns' has no member 'total'" on a line they did not write.
  ///
  /// Returns `true` if anything was reported.
  func postgrestDiagnoseAggregates(in context: some MacroExpansionContext) -> Bool {
    var reported = false
    for member in memberBlock.members {
      guard let variable = member.decl.as(VariableDeclSyntax.self) else { continue }
      let attributes = variable.attributes.compactMap { $0.as(AttributeSyntax.self) }
      let names = attributes.map(\.attributeName.trimmedDescription)
      for attribute in attributes where attribute.attributeName.trimmedDescription == "Aggregate" {
        if names.contains("Relationship") {
          context.error("@Aggregate cannot be combined with @Relationship", at: attribute)
          reported = true
        } else if postgrestAggregateReference(attribute) == nil {
          context.error(
            """
            @Aggregate requires a function and a key path to one column, written with its root, \
            as in '@Aggregate(.sum, of: \\Order.amount)', or '@Aggregate(.count)' to count rows
            """,
            at: attribute
          )
          reported = true
        }
      }
    }
    return reported
  }
}
