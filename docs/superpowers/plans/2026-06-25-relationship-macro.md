# @Relationship Macro Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement `@Relationship` support: type-safe KeyPath FK declarations in `@SelectionOf`, with a compile-time error when `@Relationship` appears in `@Table`.

**Architecture:** Two sequential tasks — Task 1 updates the macro declaration and enforces the `@Table` restriction; Task 2 teaches `SelectionOfMacro` to read `@Relationship` attributes and emit PostgREST disambiguation select strings. The macro plugin (`SupabaseMacros`) does all expansion logic; the library (`SupabaseSwiftMacros`) only exposes the declaration.

**Tech Stack:** SwiftSyntax, SwiftSyntaxMacros, SwiftDiagnostics, swift-macro-testing (`assertMacro`/`withMacroTesting`)

## Global Constraints

- All macro expansion logic lives in `Sources/SupabaseMacros/`; public declarations live in `Sources/SupabaseSwiftMacros/Macros.swift`
- No changes to `Package.swift`, `Sources/PostgREST/`, or `Sources/Supabase/`
- Run tests with `make PLATFORM=IOS XCODEBUILD_ARGUMENT=test xcodebuild`, filter with `XCODEBUILD_ARGUMENT="test -only-testing SupabaseMacrosTests"` for speed
- Format after editing: `swift-format format --in-place <changed-files-only>` then `git checkout --` any unrelated reformats
- Tests use `XCTest` + `assertMacro` from `swift-macro-testing`; follow existing patterns in `TableMacroTests.swift` and `SelectionOfMacroTests.swift`
- Commit with conventional-commit prefix: `feat(macros):`

---

### Task 1: Update `@Relationship` declaration and enforce `@Table` restriction

**Files:**
- Modify: `Sources/SupabaseSwiftMacros/Macros.swift`
- Modify: `Sources/SupabaseMacros/TableMacro.swift`
- Test: `Tests/SupabaseMacrosTests/TableMacroTests.swift`

**Interfaces:**
- Produces: `@Relationship(_ keyPath: AnyKeyPath)` macro declaration
- Produces: `TableMacroDiagnostic.relationshipNotAllowed` diagnostic
- Produces: `testFullTableExpansion` without relationship field; `testRelationshipOnTableDiagnostic`

- [ ] **Step 1: Write the failing diagnostic test**

Open `Tests/SupabaseMacrosTests/TableMacroTests.swift`. The existing `testFullTableExpansion` uses `@Relationship("user_id", references: Profile.self)` which must be removed. And there's no `testRelationshipOnTableDiagnostic` yet. Update the file to:

```swift
import MacroTesting
import XCTest

@testable import SupabaseMacros

final class TableMacroTests: XCTestCase {
  override func invokeTest() {
    withMacroTesting(
      macros: [
        "Table": TableMacro.self,
        "PrimaryKey": PrimaryKeyMacro.self,
        "Default": DefaultMacro.self,
        "Column": ColumnMacro.self,
        "Relationship": RelationshipMacro.self,
      ]
    ) { super.invokeTest() }
  }

  func testFullTableExpansion() {
    assertMacro {
      """
      @Table("todos")
      public struct Todo {
        @PrimaryKey public var id: UUID
        public var title: String
        @Default public var isComplete: Bool
        @Column("user_id") public var userId: UUID
      }
      """
    } expansion: {
      #"""
      public struct Todo {
        @PrimaryKey public var id: UUID
        public var title: String
        @Default public var isComplete: Bool
        @Column("user_id") public var userId: UUID

        public struct Insert: Encodable {
          public var title: String
          public var isComplete: Bool? = nil
          public var userId: UUID
          public enum CodingKeys: String, CodingKey {
            case title
            case isComplete = "is_complete"
            case userId = "user_id"
          }
        }

        public struct Update: Encodable {
          public var title: String? = nil
          public var isComplete: Bool? = nil
          public var userId: UUID? = nil
          public enum CodingKeys: String, CodingKey {
            case title
            case isComplete = "is_complete"
            case userId = "user_id"
          }
        }

        public enum CodingKeys: String, CodingKey {
            case id
            case title
            case isComplete = "is_complete"
            case userId = "user_id"
        }

        public static func columnName<V>(for keyPath: KeyPath<Todo, V>) -> String {
          let erased = keyPath as AnyKeyPath
          if erased == \Todo.id {
            return "id"
          }
          if erased == \Todo.title {
            return "title"
          }
          if erased == \Todo.isComplete {
            return "is_complete"
          }
          if erased == \Todo.userId {
            return "user_id"
          }
          preconditionFailure("Unknown column keypath on Todo — macro bug")
        }
      }

      extension Todo: TableRepresentable {
        public static let tableName = "todos"
        public static let schema = "public"
        public static let selectString = "*"
      }
      """#
    }
  }

  func testRelationshipOnTableDiagnostic() {
    assertMacro {
      #"""
      @Table("todos")
      public struct Todo {
        @PrimaryKey public var id: UUID
        @Relationship(\Profile.userId) public var profile: Profile?
      }
      """#
    } diagnostics: {
      #"""
      @Table("todos")
      public struct Todo {
        @PrimaryKey public var id: UUID
        @Relationship(\Profile.userId) public var profile: Profile?
        ┬─────────────────────────────
        ╰─ 🛑 '@Relationship' fields are not allowed in '@Table'. Declare a '@SelectionOf' struct to join related tables.
      }
      """#
    }
  }

  func testReadOnlyTableExpansion() {
    assertMacro {
      """
      @Table("todo_stats", readOnly: true)
      public struct TodoStats {
        public var userId: UUID
        public var totalCount: Int
      }
      """
    } expansion: {
      #"""
      public struct TodoStats {
        public var userId: UUID
        public var totalCount: Int

        public enum CodingKeys: String, CodingKey {
            case userId = "user_id"
            case totalCount = "total_count"
        }

        public static func columnName<V>(for keyPath: KeyPath<TodoStats, V>) -> String {
          let erased = keyPath as AnyKeyPath
          if erased == \TodoStats.userId {
            return "user_id"
          }
          if erased == \TodoStats.totalCount {
            return "total_count"
          }
          preconditionFailure("Unknown column keypath on TodoStats — macro bug")
        }
      }

      extension TodoStats: ReadOnlyTableRepresentable {
        public static let tableName = "todo_stats"
        public static let schema = "public"
        public static let selectString = "*"
      }
      """#
    }
  }

  func testNonStructDiagnostic() {
    assertMacro {
      """
      @Table("foo")
      enum Foo {}
      """
    } diagnostics: {
      """
      @Table("foo")
      ┬────────────
      ╰─ 🛑 @Table can only be applied to structs
      enum Foo {}
      """
    }
  }
}
```

- [ ] **Step 2: Run tests to confirm failures**

```bash
make PLATFORM=IOS XCODEBUILD_ARGUMENT="test -only-testing SupabaseMacrosTests/TableMacroTests" xcodebuild 2>&1 | tail -30
```

Expected: `testFullTableExpansion` fails (snapshot mismatch — `profile` still in output); `testRelationshipOnTableDiagnostic` fails (no diagnostic emitted).

- [ ] **Step 3: Update `@Relationship` declaration in `Macros.swift`**

Replace the entire `@Relationship` declaration at the bottom of `Sources/SupabaseSwiftMacros/Macros.swift`:

```swift
/// Declares a foreign-key join in a `@SelectionOf` struct.
/// Not allowed in `@Table` structs — the table row type has no embedded relationships.
///
/// The referenced table type is inferred from the field's type annotation
/// (Optional and Array wrappers are unwrapped automatically).
///
/// - Parameter keyPath: Key path to the FK column on the owning table.
///   Use the explicit root form `\Message.senderId` to identify which table owns the FK.
@attached(peer)
public macro Relationship(_ keyPath: AnyKeyPath) =
  #externalMacro(module: "SupabaseMacros", type: "RelationshipMacro")
```

- [ ] **Step 4: Add `relationshipNotAllowed` diagnostic and enforcement to `TableMacro.swift`**

In `Sources/SupabaseMacros/TableMacro.swift`:

**4a.** Add the new case to `TableMacroDiagnostic`:

```swift
enum TableMacroDiagnostic: DiagnosticMessage {
  case notAStruct
  case relationshipNotAllowed

  var message: String {
    switch self {
    case .notAStruct:
      return "@Table can only be applied to structs"
    case .relationshipNotAllowed:
      return "'@Relationship' fields are not allowed in '@Table'. Declare a '@SelectionOf' struct to join related tables."
    }
  }
  var diagnosticID: MessageID { .init(domain: "SupabaseMacros", id: "\(self)") }
  var severity: DiagnosticSeverity { .error }
}
```

**4b.** In `expansion(of:providingMembersOf:in:)`, add a relationship check immediately after the `guard let structDecl` block (before `let args = try TableArgs(...)`):

```swift
public static func expansion(
  of node: AttributeSyntax,
  providingMembersOf declaration: some DeclGroupSyntax,
  in context: some MacroExpansionContext
) throws -> [DeclSyntax] {
  guard let structDecl = declaration.as(StructDeclSyntax.self) else {
    context.diagnose(Diagnostic(node: node, message: TableMacroDiagnostic.notAStruct))
    return []
  }

  // @Relationship is not allowed in @Table — emit diagnostic on each offending attribute
  var hasRelationshipFields = false
  for member in structDecl.memberBlock.members {
    guard let varDecl = member.decl.as(VariableDeclSyntax.self) else { continue }
    if let relAttr = varDecl.attributes.attribute(named: "Relationship") {
      context.diagnose(Diagnostic(node: relAttr, message: TableMacroDiagnostic.relationshipNotAllowed))
      hasRelationshipFields = true
    }
  }
  if hasRelationshipFields { return [] }

  // ... rest of the method unchanged
```

**4c.** In `expansion(of:attachedTo:providingExtensionsOf:conformingTo:in:)`, add the same check (no diagnostic re-emit, just bail):

```swift
public static func expansion(
  of node: AttributeSyntax,
  attachedTo declaration: some DeclGroupSyntax,
  providingExtensionsOf type: some TypeSyntaxProtocol,
  conformingTo protocols: [TypeSyntax],
  in context: some MacroExpansionContext
) throws -> [ExtensionDeclSyntax] {
  // Suppress extension when @Relationship fields are present (diagnosed in MemberMacro)
  if let structDecl = declaration.as(StructDeclSyntax.self) {
    let hasRelationship = structDecl.memberBlock.members.contains { member in
      guard let varDecl = member.decl.as(VariableDeclSyntax.self) else { return false }
      return varDecl.attributes.attribute(named: "Relationship") != nil
    }
    if hasRelationship { return [] }
  }

  // ... rest of the method unchanged
```

**4d.** Remove the now-dead `isRelationship` filters from the helper functions. In `makeInsert`:

```swift
// Change:
let insertProps = props.filter { !$0.isPrimaryKey && !$0.isRelationship }
// To:
let insertProps = props.filter { !$0.isPrimaryKey }
```

In `makeUpdate`:

```swift
// Change:
let updateProps = props.filter { !$0.isPrimaryKey && !$0.isRelationship }
// To:
let updateProps = props.filter { !$0.isPrimaryKey }
```

In `makeColumnName`:

```swift
// Change:
let columns = props.filter { !$0.isRelationship }
// To:
let columns = props
```

In `makeCodingKeys`, remove the comment that says "relationships too — needed for embedded response decoding" (it's no longer accurate). The function body is unchanged.

- [ ] **Step 5: Run tests to confirm they pass**

```bash
make PLATFORM=IOS XCODEBUILD_ARGUMENT="test -only-testing SupabaseMacrosTests/TableMacroTests" xcodebuild 2>&1 | tail -30
```

Expected: all 4 tests pass.

If `testRelationshipOnTableDiagnostic` fails with a different diagnostic format, update the `diagnostics:` string to match the actual output printed by the test runner.

- [ ] **Step 6: Format and commit**

```bash
swift-format format --in-place \
  Sources/SupabaseSwiftMacros/Macros.swift \
  Sources/SupabaseMacros/TableMacro.swift \
  Tests/SupabaseMacrosTests/TableMacroTests.swift

git add Sources/SupabaseSwiftMacros/Macros.swift \
        Sources/SupabaseMacros/TableMacro.swift \
        Tests/SupabaseMacrosTests/TableMacroTests.swift

git commit -m "feat(macros): enforce @Relationship only in @SelectionOf; update macro signature to AnyKeyPath"
```

---

### Task 2: Implement `@Relationship` in `SelectionOfMacro`

**Files:**
- Modify: `Sources/SupabaseMacros/SelectionOfMacro.swift`
- Test: `Tests/SupabaseMacrosTests/SelectionOfMacroTests.swift`

**Interfaces:**
- Consumes: `RelationshipMacro.self` (registered in `withMacroTesting`)
- Consumes: `@Relationship(_ keyPath: AnyKeyPath)` declaration from Task 1
- Produces: `buildSelectLines` that emits PostgREST disambiguation strings for relationship fields
- Produces: `SelectionOfDiagnostic.nonPrimitiveRequiresRelationship(typeName:)` diagnostic

- [ ] **Step 1: Write all failing tests in `SelectionOfMacroTests.swift`**

Replace the full contents of `Tests/SupabaseMacrosTests/SelectionOfMacroTests.swift`:

```swift
import MacroTesting
import XCTest

@testable import SupabaseMacros

final class SelectionOfMacroTests: XCTestCase {
  override func invokeTest() {
    withMacroTesting(
      macros: [
        "SelectionOf": SelectionOfMacro.self,
        "Column": ColumnMacro.self,
        "Relationship": RelationshipMacro.self,
      ]
    ) { super.invokeTest() }
  }

  func testBasicProjection() {
    assertMacro {
      """
      @SelectionOf(Todo.self)
      public struct TodoSummary {
        public let id: UUID
        public let title: String
      }
      """
    } expansion: {
      """
      public struct TodoSummary {
        public let id: UUID
        public let title: String

        public enum CodingKeys: String, CodingKey {
          case id
          case title
        }
      }

      extension TodoSummary: SelectionRepresentable {
        public static var selectString: String {
          var parts: [String] = []
          parts.append("id")
          parts.append("title")
          return parts.joined(separator: ",")
        }
      }
      """
    }
  }

  // Old testNestedRelationship: non-primitive without @Relationship is now an error
  func testNestedRelationship() {
    assertMacro {
      """
      @SelectionOf(Todo.self)
      public struct TodoWithProfile {
        public let id: UUID
        public let profile: Profile
      }
      """
    } diagnostics: {
      """
      @SelectionOf(Todo.self)
      public struct TodoWithProfile {
        public let id: UUID
        public let profile: Profile
        ┬──────────────────────────
        ╰─ 🛑 Embedded type 'Profile' in '@SelectionOf' requires '@Relationship'
      }
      """
    }
  }

  func testRelationshipDisambiguationString() {
    assertMacro {
      #"""
      @SelectionOf(Message.self)
      public struct MessageWithSender {
        public var id: UUID
        public var body: String
        @Relationship(\Message.senderId) public var sender: User
      }
      """#
    } expansion: {
      #"""
      public struct MessageWithSender {
        public var id: UUID
        public var body: String
        public var sender: User

        public enum CodingKeys: String, CodingKey {
          case id
          case body
          case sender
        }
      }

      extension MessageWithSender: SelectionRepresentable {
        public static var selectString: String {
          var parts: [String] = []
          parts.append("id")
          parts.append("body")
          parts.append("sender:\(User.tableName)!\(Message.columnName(for: \.senderId))(\(User.selectString))")
          return parts.joined(separator: ",")
        }
      }
      """#
    }
  }

  func testRelationshipOptional() {
    assertMacro {
      #"""
      @SelectionOf(Message.self)
      public struct MessageView {
        public var id: UUID
        @Relationship(\Message.senderId) public var sender: User?
      }
      """#
    } expansion: {
      #"""
      public struct MessageView {
        public var id: UUID
        public var sender: User?

        public enum CodingKeys: String, CodingKey {
          case id
          case sender
        }
      }

      extension MessageView: SelectionRepresentable {
        public static var selectString: String {
          var parts: [String] = []
          parts.append("id")
          parts.append("sender:\(User.tableName)!\(Message.columnName(for: \.senderId))(\(User.selectString))")
          return parts.joined(separator: ",")
        }
      }
      """#
    }
  }

  func testRelationshipArray() {
    assertMacro {
      #"""
      @SelectionOf(User.self)
      public struct UserWithTodos {
        public var id: UUID
        @Relationship(\Todo.userId) public var todos: [Todo]
      }
      """#
    } expansion: {
      #"""
      public struct UserWithTodos {
        public var id: UUID
        public var todos: [Todo]

        public enum CodingKeys: String, CodingKey {
          case id
          case todos
        }
      }

      extension UserWithTodos: SelectionRepresentable {
        public static var selectString: String {
          var parts: [String] = []
          parts.append("id")
          parts.append("todos:\(Todo.tableName)!\(Todo.columnName(for: \.userId))(\(Todo.selectString))")
          return parts.joined(separator: ",")
        }
      }
      """#
    }
  }

  func testMultipleRelationships() {
    assertMacro {
      #"""
      @SelectionOf(Message.self)
      public struct MessageWithParticipants {
        public var id: UUID
        @Relationship(\Message.senderId) public var sender: User
        @Relationship(\Message.receiverId) public var receiver: User
      }
      """#
    } expansion: {
      #"""
      public struct MessageWithParticipants {
        public var id: UUID
        public var sender: User
        public var receiver: User

        public enum CodingKeys: String, CodingKey {
          case id
          case sender
          case receiver
        }
      }

      extension MessageWithParticipants: SelectionRepresentable {
        public static var selectString: String {
          var parts: [String] = []
          parts.append("id")
          parts.append("sender:\(User.tableName)!\(Message.columnName(for: \.senderId))(\(User.selectString))")
          parts.append("receiver:\(User.tableName)!\(Message.columnName(for: \.receiverId))(\(User.selectString))")
          return parts.joined(separator: ",")
        }
      }
      """#
    }
  }

  func testNonPrimitiveWithoutRelationshipDiagnostic() {
    assertMacro {
      """
      @SelectionOf(Message.self)
      public struct MessageView {
        public var id: UUID
        public var sender: User
      }
      """
    } diagnostics: {
      """
      @SelectionOf(Message.self)
      public struct MessageView {
        public var id: UUID
        public var sender: User
        ┬──────────────────────
        ╰─ 🛑 Embedded type 'User' in '@SelectionOf' requires '@Relationship'
      }
      """
    }
  }

  func testColumnAnnotationOverridesSnakeCase() {
    assertMacro {
      """
      @SelectionOf(Todo.self)
      public struct TodoUserId {
        public let id: UUID
        @Column("user_id") public let userId: UUID
      }
      """
    } expansion: {
      """
      public struct TodoUserId {
        public let id: UUID
        public let userId: UUID

        public enum CodingKeys: String, CodingKey {
          case id
          case userId = "user_id"
        }
      }

      extension TodoUserId: SelectionRepresentable {
        public static var selectString: String {
          var parts: [String] = []
          parts.append("id")
          parts.append("user_id")
          return parts.joined(separator: ",")
        }
      }
      """
    }
  }
}
```

- [ ] **Step 2: Run tests to confirm failures**

```bash
make PLATFORM=IOS XCODEBUILD_ARGUMENT="test -only-testing SupabaseMacrosTests/SelectionOfMacroTests" xcodebuild 2>&1 | tail -40
```

Expected: `testNestedRelationship` fails (still produces expansion instead of diagnostic); new relationship tests fail (no expansion generated); `testBasicProjection` and `testColumnAnnotationOverridesSnakeCase` still pass.

- [ ] **Step 3: Rewrite `SelectionOfMacro.swift`**

Replace the full file `Sources/SupabaseMacros/SelectionOfMacro.swift`:

```swift
import Foundation
import SwiftDiagnostics
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros

// Types that map directly to PostgREST columns (not nested relationships).
private let knownPrimitives: Set<String> = [
  "UUID", "String", "Int", "Int8", "Int16", "Int32", "Int64",
  "UInt", "UInt8", "UInt16", "UInt32", "UInt64",
  "Bool", "Double", "Float", "Decimal", "Date", "Data", "URL", "AnyJSON",
]

public struct SelectionOfMacro: MemberMacro, ExtensionMacro {

  // MARK: - ExtensionMacro — adds SelectionRepresentable with computed selectString

  public static func expansion(
    of node: AttributeSyntax,
    attachedTo declaration: some DeclGroupSyntax,
    providingExtensionsOf type: some TypeSyntaxProtocol,
    conformingTo protocols: [TypeSyntax],
    in context: some MacroExpansionContext
  ) throws -> [ExtensionDeclSyntax] {
    guard let structDecl = declaration.as(StructDeclSyntax.self) else {
      context.diagnose(Diagnostic(node: node, message: SelectionOfDiagnostic.notAStruct))
      return []
    }

    let parentTableName = parseParentTableName(from: node) ?? ""
    let typeName = type.trimmedDescription
    let (selectLines, hasErrors) = buildSelectLines(
      from: structDecl,
      parentTableName: parentTableName,
      context: context
    )

    if hasErrors { return [] }

    let body = selectLines.joined(separator: "\n")
    let ext: DeclSyntax = """
      extension \(raw: typeName): SelectionRepresentable {
        public static var selectString: String {
          var parts: [String] = []
      \(raw: body)
          return parts.joined(separator: ",")
        }
      }
      """
    return [ext.cast(ExtensionDeclSyntax.self)]
  }

  // MARK: - MemberMacro — adds CodingKeys

  public static func expansion(
    of node: AttributeSyntax,
    providingMembersOf declaration: some DeclGroupSyntax,
    in context: some MacroExpansionContext
  ) throws -> [DeclSyntax] {
    guard let structDecl = declaration.as(StructDeclSyntax.self) else { return [] }
    let props = parseLetProperties(from: structDecl)
    let keyLines =
      props
      .map {
        $0.name == $0.columnName
          ? "  case \($0.name)"
          : "  case \($0.name) = \"\($0.columnName)\""
      }
      .joined(separator: "\n")

    return [
      """
      public enum CodingKeys: String, CodingKey {
      \(raw: keyLines)
      }
      """
    ]
  }
}

// MARK: - Property parsing for @SelectionOf (handles let and var bindings)

private struct LetPropertyInfo {
  let name: String
  let columnName: String  // JSON key for CodingKeys
  let typeText: String
}

private func parseLetProperties(from decl: StructDeclSyntax) -> [LetPropertyInfo] {
  var result: [LetPropertyInfo] = []
  for member in decl.memberBlock.members {
    guard
      let varDecl = member.decl.as(VariableDeclSyntax.self),
      let binding = varDecl.bindings.first,
      let pattern = binding.pattern.as(IdentifierPatternSyntax.self),
      let typeAnnotation = binding.typeAnnotation,
      binding.accessorBlock == nil
    else { continue }

    let name = pattern.identifier.text
    let attrs = varDecl.attributes
    let isRelationship = attrs.containsAttribute(named: "Relationship")

    // Relationship fields use the field name as the JSON key (PostgREST alias),
    // not the snake_case column name. @Column override is irrelevant for relationships.
    let columnName: String
    if isRelationship {
      columnName = name
    } else if let colAttr = attrs.attribute(named: "Column"),
      let args = colAttr.arguments?.as(LabeledExprListSyntax.self),
      let first = args.first,
      let strLit = first.expression.as(StringLiteralExprSyntax.self),
      let seg = strLit.segments.first?.as(StringSegmentSyntax.self)
    {
      columnName = seg.content.text
    } else {
      columnName = camelToSnake(name)
    }

    result.append(
      LetPropertyInfo(
        name: name,
        columnName: columnName,
        typeText: typeAnnotation.type.trimmedDescription
      ))
  }
  return result
}

// MARK: - Select string builder

private func buildSelectLines(
  from decl: StructDeclSyntax,
  parentTableName: String,
  context: some MacroExpansionContext
) -> (lines: [String], hasErrors: Bool) {
  var lines: [String] = []
  var hasErrors = false

  for member in decl.memberBlock.members {
    guard
      let varDecl = member.decl.as(VariableDeclSyntax.self),
      let binding = varDecl.bindings.first,
      let pattern = binding.pattern.as(IdentifierPatternSyntax.self),
      let typeAnnotation = binding.typeAnnotation,
      binding.accessorBlock == nil
    else { continue }

    let name = pattern.identifier.text
    let attrs = varDecl.attributes

    // Resolve column name for primitive fields (@Column override or camelToSnake)
    let columnName: String
    if let colAttr = attrs.attribute(named: "Column"),
      let args = colAttr.arguments?.as(LabeledExprListSyntax.self),
      let first = args.first,
      let strLit = first.expression.as(StringLiteralExprSyntax.self),
      let seg = strLit.segments.first?.as(StringSegmentSyntax.self)
    {
      columnName = seg.content.text
    } else {
      columnName = camelToSnake(name)
    }

    // Determine the base Swift type (strip Optional and Array wrappers)
    let baseType = unwrapBaseType(typeAnnotation.type.trimmedDescription)

    if knownPrimitives.contains(baseType) {
      // Plain scalar column
      lines.append("    parts.append(\"\(columnName)\")")
    } else if let relAttr = attrs.attribute(named: "Relationship") {
      // @Relationship — generate PostgREST disambiguation: alias:table!fk(subselect)
      let (rootType, fkProperty) = parseRelationshipKeyPath(
        from: relAttr, parentTableName: parentTableName)
      // Produces: parts.append("name:\(BaseType.tableName)!\(RootType.columnName(for: \.fkProp))(\(BaseType.selectString))")
      lines.append(
        "    parts.append(\"\(name):\\(\(baseType).tableName)!\\(\(rootType).columnName(for: \\.\(fkProperty)))(\\(\(baseType).selectString))\")"
      )
    } else {
      // Non-primitive without @Relationship — emit diagnostic
      context.diagnose(
        Diagnostic(
          node: Syntax(varDecl),
          message: SelectionOfDiagnostic.nonPrimitiveRequiresRelationship(typeName: baseType)
        ))
      hasErrors = true
    }
  }
  return (lines, hasErrors)
}

// MARK: - Helpers

/// Parses the table type name from @SelectionOf(Message.self) → "Message".
private func parseParentTableName(from node: AttributeSyntax) -> String? {
  guard
    let args = node.arguments?.as(LabeledExprListSyntax.self),
    let first = args.first,
    let memberAccess = first.expression.as(MemberAccessExprSyntax.self),
    let base = memberAccess.base?.as(DeclReferenceExprSyntax.self)
  else { return nil }
  return base.baseName.text
}

/// Strips Optional (`?`) and Array (`[T]`) wrappers to get the base type name.
private func unwrapBaseType(_ typeText: String) -> String {
  var t = typeText
  if t.hasSuffix("?") { t = String(t.dropLast()) }
  if t.hasPrefix("[") && t.hasSuffix("]") {
    t = String(t.dropFirst().dropLast())
    if t.hasSuffix("?") { t = String(t.dropLast()) }
  }
  return t
}

/// Extracts (rootTypeName, fkPropertyName) from a @Relationship attribute.
/// For \Message.senderId → ("Message", "senderId").
/// For \.senderId → (parentTableName, "senderId").
private func parseRelationshipKeyPath(
  from attr: AttributeSyntax,
  parentTableName: String
) -> (rootType: String, fkProperty: String) {
  guard
    let args = attr.arguments?.as(LabeledExprListSyntax.self),
    let first = args.first,
    let keyPathExpr = first.expression.as(KeyPathExprSyntax.self)
  else { return (parentTableName, "") }

  let rootType: String
  if let root = keyPathExpr.root {
    rootType = root.trimmedDescription
  } else {
    rootType = parentTableName
  }

  let fkProperty =
    keyPathExpr.components
    .compactMap { $0.component.as(KeyPathPropertyComponentSyntax.self) }
    .first?.declName.baseName.text ?? ""

  return (rootType, fkProperty)
}

// MARK: - Diagnostics

enum SelectionOfDiagnostic: DiagnosticMessage {
  case notAStruct
  case nonPrimitiveRequiresRelationship(typeName: String)

  var message: String {
    switch self {
    case .notAStruct:
      return "@SelectionOf can only be applied to structs"
    case .nonPrimitiveRequiresRelationship(let typeName):
      return "Embedded type '\(typeName)' in '@SelectionOf' requires '@Relationship'"
    }
  }
  var diagnosticID: MessageID { .init(domain: "SupabaseMacros", id: "\(self)") }
  var severity: DiagnosticSeverity { .error }
}
```

- [ ] **Step 4: Run tests to confirm they pass**

```bash
make PLATFORM=IOS XCODEBUILD_ARGUMENT="test -only-testing SupabaseMacrosTests/SelectionOfMacroTests" xcodebuild 2>&1 | tail -40
```

Expected: all 8 tests pass.

If any diagnostic format test fails, the test runner prints the exact expected string — copy it verbatim into the `diagnostics:` closure. If any expansion format test fails, copy the printed expansion into the `expansion:` closure.

- [ ] **Step 5: Run the full macro test suite**

```bash
make PLATFORM=IOS XCODEBUILD_ARGUMENT="test -only-testing SupabaseMacrosTests" xcodebuild 2>&1 | tail -20
```

Expected: all tests pass (both `TableMacroTests` and `SelectionOfMacroTests`).

- [ ] **Step 6: Format and commit**

```bash
swift-format format --in-place \
  Sources/SupabaseMacros/SelectionOfMacro.swift \
  Tests/SupabaseMacrosTests/SelectionOfMacroTests.swift

git add Sources/SupabaseMacros/SelectionOfMacro.swift \
        Tests/SupabaseMacrosTests/SelectionOfMacroTests.swift

git commit -m "feat(macros): implement @Relationship in @SelectionOf with KeyPath FK and disambiguation select strings"
```
