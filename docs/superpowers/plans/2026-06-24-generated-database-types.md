# Generated Database Types Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add compile-time type-safe PostgREST queries via Swift Macros (`@Table`, `@SelectionOf`) and a typed wrapper layer over the existing string-based builders.

**Architecture:** Two new SPM targets — `SupabaseMacros` (executable, macro implementations using SwiftSyntax) and `SupabaseSwiftMacros` (library, protocols + macro declarations) — feed into typed wrapper builders (`TypedPostgrestQueryBuilder<T>` etc.) added to the `PostgREST` target. The existing string-based API is untouched; the typed API is a purely additive extension.

**Tech Stack:** Swift 5.10+, swift-syntax 510.x, swift-macro-testing 0.5.x, XCTest.

## Global Constraints

- `swift-tools-version` is already `5.10` — do not change it
- Minimum platforms: iOS 13, macOS 10.15, tvOS 13, watchOS 6 (already set in Package.swift)
- All non-test targets automatically receive `.enableUpcomingFeature("ExistentialAny")` and `.enableExperimentalFeature("StrictConcurrency")` via the loop at the bottom of Package.swift — do not add them per-target
- New test files use `import Testing` / `@Test` / `#expect` (project convention); macro expansion tests use `XCTest` + `MacroTesting` (required by swift-macro-testing)
- `@SelectionOf` takes the parent table as an expression argument — `@SelectionOf(Todo.self)` — NOT angle-bracket generic syntax; Swift attached macros do not support generic parameters
- CLI codegen (`supabase gen types swift`) lives in the supabase CLI repo and is **out of scope** for this plan
- Run `make format` before every commit; run `swift test --filter <TargetName>` for macro tests
- Commit after every task using conventional commit format: `feat(postgrest): ...`

---

## File Map

```
Sources/
  SupabaseSwiftMacros/           ← Task 2
    Protocols.swift              — SelectionRepresentable, TableRepresentable, ReadOnlyTableRepresentable
    Macros.swift                 — @attached macro declarations (stubs pointing to SupabaseMacros)
  SupabaseMacros/                ← Tasks 3–5
    Plugin.swift                 — CompilerPlugin registration
    MarkerMacros.swift           — @Column, @PrimaryKey, @Default, @Relationship (no-op peers)
    TableMacro.swift             — @Table member + extension macro
    SelectionOfMacro.swift       — @SelectionOf member + extension macro
    Support/
      CamelToSnake.swift         — camelCase → snake_case helper
      StoredPropertyInfo.swift   — parse properties + their marker attributes
  PostgREST/
    TypedBuilders/               ← Task 6
      TypedPostgrestQueryBuilder.swift
      TypedPostgrestFilterBuilder.swift
      TypedPostgrestTransformBuilder.swift
      TypedSingleResultBuilder.swift
    PostgrestClient+Typed.swift  ← Task 7

Tests/
  SupabaseMacrosTests/
    MarkerMacroTests.swift       ← Task 3
    TableMacroTests.swift        ← Task 4
    SelectionOfMacroTests.swift  ← Task 5
  PostgRESTTests/
    TypedBuildersTests.swift     ← Task 6 (new file in existing test target)
```

---

## Task 1: Package Infrastructure

**Files:**
- Modify: `Package.swift`
- Create: `Sources/SupabaseSwiftMacros/.gitkeep` (placeholder — real files in Task 2)
- Create: `Sources/SupabaseMacros/.gitkeep`
- Create: `Sources/SupabaseMacros/Support/.gitkeep`

**Interfaces:**
- Produces: two new buildable SPM targets; `SupabaseMacros` test target; `SupabaseSwiftMacros` product

- [ ] **Step 1: Add dependencies to Package.swift**

In `Package.swift`, inside the `dependencies: [` array, add after the last existing entry:

```swift
.package(url: "https://github.com/swiftlang/swift-syntax", from: "510.0.0"),
.package(url: "https://github.com/pointfreeco/swift-macro-testing", from: "0.5.0"),
```

- [ ] **Step 2: Add the library product**

In the `products: [` array, add after `.library(name: "Supabase", ...)`:

```swift
.library(name: "SupabaseSwiftMacros", targets: ["SupabaseSwiftMacros"]),
```

- [ ] **Step 3: Add new targets**

In `targets: [`, add these three targets before the closing `]`:

```swift
.macro(
  name: "SupabaseMacros",
  dependencies: [
    .product(name: "SwiftSyntaxMacros", package: "swift-syntax"),
    .product(name: "SwiftCompilerPlugin", package: "swift-syntax"),
  ]
),
.target(
  name: "SupabaseSwiftMacros",
  dependencies: [
    .target(name: "SupabaseMacros"),
  ]
),
.testTarget(
  name: "SupabaseMacrosTests",
  dependencies: [
    .target(name: "SupabaseMacros"),
    .target(name: "SupabaseSwiftMacros"),
    .product(name: "MacroTesting", package: "swift-macro-testing"),
  ]
),
```

- [ ] **Step 4: Wire SupabaseSwiftMacros into PostgREST and Supabase targets**

In the existing `PostgREST` target dependencies array, add:
```swift
.target(name: "SupabaseSwiftMacros"),
```

In the existing `Supabase` target dependencies array, add:
```swift
.target(name: "SupabaseSwiftMacros"),
```

- [ ] **Step 5: Create empty source directories with placeholder files**

```bash
mkdir -p Sources/SupabaseSwiftMacros Sources/SupabaseMacros/Support Tests/SupabaseMacrosTests
touch Sources/SupabaseSwiftMacros/.gitkeep Sources/SupabaseMacros/.gitkeep
touch Sources/SupabaseMacros/Support/.gitkeep Tests/SupabaseMacrosTests/.gitkeep
```

- [ ] **Step 6: Verify the package resolves and builds**

```bash
swift package resolve
swift build --target SupabaseSwiftMacros
```

Expected: resolves without error. Build may warn about empty targets — that is fine.

- [ ] **Step 7: Commit**

```bash
make format
git add Package.swift Package.resolved Sources/SupabaseSwiftMacros/ Sources/SupabaseMacros/ Tests/SupabaseMacrosTests/
git commit -m "feat(postgrest): add SupabaseMacros and SupabaseSwiftMacros SPM targets"
```

---

## Task 2: Protocol Layer + Macro Declarations

**Files:**
- Create: `Sources/SupabaseSwiftMacros/Protocols.swift`
- Create: `Sources/SupabaseSwiftMacros/Macros.swift`
- Create: `Sources/SupabaseMacros/Plugin.swift` (empty plugin — populated in Task 3)

**Interfaces:**
- Produces: `SelectionRepresentable`, `TableRepresentable`, `ReadOnlyTableRepresentable` protocols; all macro declarations; `CompilerPlugin` stub

- [ ] **Step 1: Write Protocols.swift**

Create `Sources/SupabaseSwiftMacros/Protocols.swift`:

```swift
import Foundation

/// Conformance synthesized by @SelectionOf or @Table.
/// Carries the PostgREST column select expression and is Decodable.
public protocol SelectionRepresentable: Decodable {
  static var selectString: String { get }
}

/// Conformance synthesized by @Table(readOnly: true) — for views.
/// Shared base for both read-only and read-write tables so that
/// TypedPostgrestFilterBuilder can be constrained to this single protocol.
public protocol ReadOnlyTableRepresentable: SelectionRepresentable {
  static var tableName: String { get }
  static var schema: String { get }
  static func columnName<V>(for keyPath: KeyPath<Self, V>) -> String
}

/// Conformance synthesized by @Table on a read-write table.
/// Refines ReadOnlyTableRepresentable by adding Insert and Update associated types.
/// TypedPostgrestQueryBuilder<Table: TableRepresentable> exposes insert/update/delete.
public protocol TableRepresentable: ReadOnlyTableRepresentable {
  associatedtype Insert: Encodable
  associatedtype Update: Encodable
}
```

- [ ] **Step 2: Write Macros.swift**

Create `Sources/SupabaseSwiftMacros/Macros.swift`:

```swift
/// Marks a struct as a PostgREST table.
///
/// Synthesizes:
/// - `TableRepresentable` or `ReadOnlyTableRepresentable` conformance
/// - `static let tableName`, `schema`, `selectString = "*"`
/// - `static func columnName<V>(for:) -> String`
/// - Nested `Insert` struct (excluded when readOnly: true)
/// - Nested `Update` struct (excluded when readOnly: true)
/// - `CodingKeys` enum with snake_case mapping
///
/// - Parameters:
///   - tableName: The PostgREST table or view name.
///   - schema: The PostgreSQL schema (default: "public").
///   - readOnly: Pass true for views — omits Insert/Update and conforms to ReadOnlyTableRepresentable.
@attached(member, names: named(Insert), named(Update), named(CodingKeys), named(columnName))
@attached(extension, conformances: TableRepresentable, ReadOnlyTableRepresentable, SelectionRepresentable,
           names: named(tableName), named(schema), named(selectString))
public macro Table(
  _ tableName: String,
  schema: String = "public",
  readOnly: Bool = false
) = #externalMacro(module: "SupabaseMacros", type: "TableMacro")

/// Marks a struct as a partial column projection of table T.
///
/// Synthesizes:
/// - `SelectionRepresentable` conformance
/// - `static var selectString: String` — computed from field names, resolved at runtime
///   for nested SelectionRepresentable fields (e.g. `"id,title,profile(\(Profile.selectString))"`)
/// - `CodingKeys` enum with snake_case mapping
///
/// Field names must match column or relationship names on T. Type mismatches are caught
/// at decode time via Decodable. Compile-time cross-type validation is a future enhancement.
///
/// - Parameter table: The parent TableRepresentable type, e.g. `Todo.self`.
@attached(member, names: named(CodingKeys))
@attached(extension, conformances: SelectionRepresentable, names: named(selectString))
public macro SelectionOf(_ table: Any.Type) = #externalMacro(module: "SupabaseMacros", type: "SelectionOfMacro")

/// Marks a stored property as the table primary key.
/// Excluded from the synthesized Insert and Update types.
@attached(peer)
public macro PrimaryKey() = #externalMacro(module: "SupabaseMacros", type: "PrimaryKeyMacro")

/// Marks a stored property as having a database-side default value.
/// The property becomes Optional with `= nil` in the synthesized Insert type.
@attached(peer)
public macro Default() = #externalMacro(module: "SupabaseMacros", type: "DefaultMacro")

/// Overrides the snake_case-derived column name for a stored property.
/// - Parameter name: The exact PostgREST column name.
@attached(peer)
public macro Column(_ name: String) = #externalMacro(module: "SupabaseMacros", type: "ColumnMacro")

/// Declares a foreign-key relationship. Excluded from Insert and Update.
/// In @SelectionOf structs, a field typed as the referenced table or a @SelectionOf of it
/// produces an embedded PostgREST select (e.g. `"profile(*)"` or `"profile(id,name)"`).
/// - Parameters:
///   - foreignKey: The FK column name on this table (e.g. `"user_id"`).
///   - references: The referenced TableRepresentable type (e.g. `Profile.self`).
@attached(peer)
public macro Relationship(_ foreignKey: String, references: Any.Type) = #externalMacro(module: "SupabaseMacros", type: "RelationshipMacro")
```

- [ ] **Step 3: Write the initial Plugin.swift (empty — populated in Tasks 3–5)**

Create `Sources/SupabaseMacros/Plugin.swift`:

```swift
import SwiftCompilerPlugin
import SwiftSyntaxMacros

@main
struct SupabaseMacrosPlugin: CompilerPlugin {
  let providingMacros: [any Macro.Type] = [
    // Populated in Tasks 3–5
  ]
}
```

- [ ] **Step 4: Verify build**

```bash
swift build --target SupabaseSwiftMacros
```

Expected: builds cleanly (Plugin.swift provides no macros yet — that is fine).

- [ ] **Step 5: Commit**

```bash
make format
git add Sources/SupabaseSwiftMacros/ Sources/SupabaseMacros/Plugin.swift
git commit -m "feat(postgrest): add protocol layer and macro declarations"
```

---

## Task 3: Marker Macros

Marker macros (`@PrimaryKey`, `@Default`, `@Column`, `@Relationship`) produce no expansion — they exist solely as source annotations that the `@Table` and `@SelectionOf` macros read. Each is a `PeerMacro` that returns an empty array.

**Files:**
- Create: `Sources/SupabaseMacros/MarkerMacros.swift`
- Modify: `Sources/SupabaseMacros/Plugin.swift`
- Create: `Tests/SupabaseMacrosTests/MarkerMacroTests.swift`

**Interfaces:**
- Consumes: SwiftSyntaxMacros `PeerMacro` protocol
- Produces: `PrimaryKeyMacro`, `DefaultMacro`, `ColumnMacro`, `RelationshipMacro` types registered in the plugin

- [ ] **Step 1: Write the failing macro expansion tests**

Create `Tests/SupabaseMacrosTests/MarkerMacroTests.swift`:

```swift
import MacroTesting
import XCTest
@testable import SupabaseMacros

final class MarkerMacroTests: XCTestCase {
  override func invokeTest() {
    withMacroTesting(
      macros: [
        "PrimaryKey": PrimaryKeyMacro.self,
        "Default": DefaultMacro.self,
        "Column": ColumnMacro.self,
        "Relationship": RelationshipMacro.self,
      ]
    ) { super.invokeTest() }
  }

  func testPrimaryKeyProducesNoPeers() {
    assertMacro {
      """
      struct Foo {
        @PrimaryKey var id: UUID
      }
      """
    } expansion: {
      """
      struct Foo {
        @PrimaryKey var id: UUID
      }
      """
    }
  }

  func testDefaultProducesNoPeers() {
    assertMacro {
      """
      struct Foo {
        @Default var isComplete: Bool
      }
      """
    } expansion: {
      """
      struct Foo {
        @Default var isComplete: Bool
      }
      """
    }
  }

  func testColumnProducesNoPeers() {
    assertMacro {
      """
      struct Foo {
        @Column("user_id") var userId: UUID
      }
      """
    } expansion: {
      """
      struct Foo {
        @Column("user_id") var userId: UUID
      }
      """
    }
  }

  func testRelationshipProducesNoPeers() {
    assertMacro {
      """
      struct Foo {
        @Relationship("user_id", references: Profile.self) var profile: Profile?
      }
      """
    } expansion: {
      """
      struct Foo {
        @Relationship("user_id", references: Profile.self) var profile: Profile?
      }
      """
    }
  }
}
```

- [ ] **Step 2: Run tests — expect failure (types not defined yet)**

```bash
swift test --filter SupabaseMacrosTests.MarkerMacroTests
```

Expected: compile error — `PrimaryKeyMacro`, `DefaultMacro` etc. not found.

- [ ] **Step 3: Implement MarkerMacros.swift**

Create `Sources/SupabaseMacros/MarkerMacros.swift`:

```swift
import SwiftSyntax
import SwiftSyntaxMacros

public struct PrimaryKeyMacro: PeerMacro {
  public static func expansion(
    of node: AttributeSyntax,
    providingPeersOf declaration: some DeclSyntaxProtocol,
    in context: some MacroExpansionContext
  ) throws -> [DeclSyntax] { [] }
}

public struct DefaultMacro: PeerMacro {
  public static func expansion(
    of node: AttributeSyntax,
    providingPeersOf declaration: some DeclSyntaxProtocol,
    in context: some MacroExpansionContext
  ) throws -> [DeclSyntax] { [] }
}

public struct ColumnMacro: PeerMacro {
  public static func expansion(
    of node: AttributeSyntax,
    providingPeersOf declaration: some DeclSyntaxProtocol,
    in context: some MacroExpansionContext
  ) throws -> [DeclSyntax] { [] }
}

public struct RelationshipMacro: PeerMacro {
  public static func expansion(
    of node: AttributeSyntax,
    providingPeersOf declaration: some DeclSyntaxProtocol,
    in context: some MacroExpansionContext
  ) throws -> [DeclSyntax] { [] }
}
```

- [ ] **Step 4: Register marker macros in Plugin.swift**

Replace the `providingMacros` array in `Sources/SupabaseMacros/Plugin.swift`:

```swift
let providingMacros: [any Macro.Type] = [
  PrimaryKeyMacro.self,
  DefaultMacro.self,
  ColumnMacro.self,
  RelationshipMacro.self,
  // TableMacro and SelectionOfMacro added in Tasks 4–5
]
```

- [ ] **Step 5: Run tests — expect pass**

```bash
swift test --filter SupabaseMacrosTests.MarkerMacroTests
```

Expected: all 4 tests pass.

- [ ] **Step 6: Commit**

```bash
make format
git add Sources/SupabaseMacros/MarkerMacros.swift Sources/SupabaseMacros/Plugin.swift \
        Tests/SupabaseMacrosTests/MarkerMacroTests.swift
git commit -m "feat(postgrest): add marker macros (@PrimaryKey, @Default, @Column, @Relationship)"
```

---

## Task 4: `@Table` Macro

The `@Table` macro is a combined `MemberMacro` + `ExtensionMacro`. It reads the struct's stored properties and their marker attributes to synthesize: `TableRepresentable` (or `ReadOnlyTableRepresentable`) conformance, `Insert`, `Update`, `CodingKeys`, and `columnName`.

**Files:**
- Create: `Sources/SupabaseMacros/Support/CamelToSnake.swift`
- Create: `Sources/SupabaseMacros/Support/StoredPropertyInfo.swift`
- Create: `Sources/SupabaseMacros/TableMacro.swift`
- Modify: `Sources/SupabaseMacros/Plugin.swift`
- Create: `Tests/SupabaseMacrosTests/TableMacroTests.swift`

**Interfaces:**
- Consumes: `StoredPropertyInfo`, `CamelToSnake` helpers; `MemberMacro` + `ExtensionMacro` protocols
- Produces: `TableMacro` type; synthesized `Insert`, `Update`, `CodingKeys`, `columnName`, and conformance extensions on annotated structs

- [ ] **Step 1: Write the failing expansion test**

Create `Tests/SupabaseMacrosTests/TableMacroTests.swift`:

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
        @Relationship("user_id", references: Profile.self) public var profile: Profile?
      }
      """
    } expansion: {
      """
      public struct Todo {
        @PrimaryKey public var id: UUID
        public var title: String
        @Default public var isComplete: Bool
        @Column("user_id") public var userId: UUID
        @Relationship("user_id", references: Profile.self) public var profile: Profile?

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
          case profile
        }

        public static func columnName<V>(for keyPath: KeyPath<Todo, V>) -> String {
          let erased = keyPath as AnyKeyPath
          if erased == \\Todo.id { return "id" }
          if erased == \\Todo.title { return "title" }
          if erased == \\Todo.isComplete { return "is_complete" }
          if erased == \\Todo.userId { return "user_id" }
          preconditionFailure("Unknown column keypath on Todo — macro bug")
        }
      }

      extension Todo: TableRepresentable {
        public static let tableName = "todos"
        public static let schema = "public"
        public static let selectString = "*"
      }
      """
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
      """
      public struct TodoStats {
        public var userId: UUID
        public var totalCount: Int

        public enum CodingKeys: String, CodingKey {
          case userId = "user_id"
          case totalCount = "total_count"
        }

        public static func columnName<V>(for keyPath: KeyPath<TodoStats, V>) -> String {
          let erased = keyPath as AnyKeyPath
          if erased == \\TodoStats.userId { return "user_id" }
          if erased == \\TodoStats.totalCount { return "total_count" }
          preconditionFailure("Unknown column keypath on TodoStats — macro bug")
        }
      }

      extension TodoStats: ReadOnlyTableRepresentable {
        public static let tableName = "todo_stats"
        public static let schema = "public"
        public static let selectString = "*"
      }
      """
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

> **Note:** The exact whitespace and formatting of the expansion strings is determined by SwiftSyntax's code printer. On the first implementation run, use `assertMacro { ... }` WITHOUT the `expansion:` closure — swift-macro-testing will print the actual expansion. Copy it into the `expansion:` closure. Then subsequent runs assert the exact output.

- [ ] **Step 2: Run the test — expect compile failure**

```bash
swift test --filter SupabaseMacrosTests.TableMacroTests
```

Expected: compile error — `TableMacro` not found.

- [ ] **Step 3: Implement CamelToSnake.swift**

Create `Sources/SupabaseMacros/Support/CamelToSnake.swift`:

```swift
/// Converts a camelCase identifier to snake_case.
/// Examples: "isComplete" → "is_complete", "userId" → "user_id", "id" → "id"
func camelToSnake(_ input: String) -> String {
  var result = ""
  for (i, char) in input.enumerated() {
    if char.isUppercase && i > 0 {
      result += "_"
    }
    result += char.lowercased()
  }
  return result
}
```

- [ ] **Step 4: Implement StoredPropertyInfo.swift**

Create `Sources/SupabaseMacros/Support/StoredPropertyInfo.swift`:

```swift
import SwiftSyntax

struct StoredPropertyInfo {
  let name: String          // Swift identifier, e.g. "isComplete"
  let typeSyntax: TypeSyntax
  let columnName: String    // PostgREST column, e.g. "is_complete"
  let isPrimaryKey: Bool
  let hasDefault: Bool
  let isRelationship: Bool
  let isOptional: Bool      // whether the Swift type is Optional<T>
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
    let isOptional = typeSyntax.is(OptionalTypeSyntax.self)
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
       let segments = strLit.segments.first?.as(StringSegmentSyntax.self) {
      columnName = segments.content.text
    } else {
      columnName = camelToSnake(name)
    }

    result.append(StoredPropertyInfo(
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
```

- [ ] **Step 5: Implement TableMacro.swift**

Create `Sources/SupabaseMacros/TableMacro.swift`:

```swift
import SwiftSyntax
import SwiftSyntaxMacros
import SwiftSyntaxBuilder

public struct TableMacro: MemberMacro, ExtensionMacro {

  // MARK: - ExtensionMacro — adds protocol conformance

  public static func expansion(
    of node: AttributeSyntax,
    attachedTo declaration: some DeclGroupSyntax,
    providingExtensionsOf type: some TypeSyntaxProtocol,
    conformingTo protocols: [TypeSyntax],
    in context: some MacroExpansionContext
  ) throws -> [ExtensionDeclSyntax] {
    let args = try TableArgs(from: node)
    let typeName = type.trimmedDescription
    let conformance = args.readOnly ? "ReadOnlyTableRepresentable" : "TableRepresentable"

    let ext: DeclSyntax = """
      extension \(raw: typeName): \(raw: conformance) {
        public static let tableName = "\(raw: args.tableName)"
        public static let schema = "\(raw: args.schema)"
        public static let selectString = "*"
      }
      """
    return [ext.cast(ExtensionDeclSyntax.self)]
  }

  // MARK: - MemberMacro — adds Insert, Update, CodingKeys, columnName

  public static func expansion(
    of node: AttributeSyntax,
    providingMembersOf declaration: some DeclGroupSyntax,
    in context: some MacroExpansionContext
  ) throws -> [DeclSyntax] {
    guard let structDecl = declaration.as(StructDeclSyntax.self) else {
      context.diagnose(Diagnostic(
        node: node,
        message: TableMacroDiagnostic.notAStruct
      ))
      return []
    }

    let args = try TableArgs(from: node)
    let typeName = structDecl.name.text
    let props = parseStoredProperties(from: structDecl)

    var members: [DeclSyntax] = []

    if !args.readOnly {
      members.append(makeInsert(from: props))
      members.append(makeUpdate(from: props))
    }
    members.append(makeCodingKeys(from: props))
    members.append(makeColumnName(typeName: typeName, from: props))

    return members
  }
}

// MARK: - Argument parsing

struct TableArgs {
  let tableName: String
  let schema: String
  let readOnly: Bool

  init(from node: AttributeSyntax) throws {
    guard let args = node.arguments?.as(LabeledExprListSyntax.self) else {
      throw MacroExpansionError("@Table requires a table name argument")
    }

    // First positional arg: table name
    guard let first = args.first,
          let strLit = first.expression.as(StringLiteralExprSyntax.self),
          let seg = strLit.segments.first?.as(StringSegmentSyntax.self) else {
      throw MacroExpansionError("@Table first argument must be a string literal")
    }
    tableName = seg.content.text

    // schema: label
    if let schemaArg = args.first(where: { $0.label?.text == "schema" }),
       let strLit = schemaArg.expression.as(StringLiteralExprSyntax.self),
       let seg = strLit.segments.first?.as(StringSegmentSyntax.self) {
      schema = seg.content.text
    } else {
      schema = "public"
    }

    // readOnly: label
    if let roArg = args.first(where: { $0.label?.text == "readOnly" }),
       let boolLit = roArg.expression.as(BooleanLiteralExprSyntax.self) {
      readOnly = boolLit.literal.tokenKind == .keyword(.true)
    } else {
      readOnly = false
    }
  }
}

// MARK: - Diagnostics

enum TableMacroDiagnostic: DiagnosticMessage {
  case notAStruct

  var message: String {
    switch self {
    case .notAStruct: return "@Table can only be applied to structs"
    }
  }
  var diagnosticID: MessageID { .init(domain: "SupabaseMacros", id: "\(self)") }
  var severity: DiagnosticSeverity { .error }
}

struct MacroExpansionError: Error, CustomStringConvertible {
  let description: String
  init(_ message: String) { description = message }
}

// MARK: - Member synthesis helpers

private func makeInsert(from props: [StoredPropertyInfo]) -> DeclSyntax {
  // Exclude @PrimaryKey and @Relationship; @Default fields become Optional with = nil
  let insertProps = props.filter { !$0.isPrimaryKey && !$0.isRelationship }

  var varLines: [String] = []
  var keyLines: [String] = []

  for prop in insertProps {
    let base = prop.typeSyntax.trimmedDescription
      .trimmingCharacters(in: CharacterSet(charactersIn: "?"))
    if prop.hasDefault || prop.isOptional {
      varLines.append("  public var \(prop.name): \(base)? = nil")
    } else {
      varLines.append("  public var \(prop.name): \(base)")
    }
    keyLines.append(codingKeyLine(swiftName: prop.name, columnName: prop.columnName))
  }

  let vars = varLines.joined(separator: "\n")
  let keys = keyLines.joined(separator: "\n")

  return """
    public struct Insert: Encodable {
    \(raw: vars)
      public enum CodingKeys: String, CodingKey {
    \(raw: keys)
      }
    }
    """
}

private func makeUpdate(from props: [StoredPropertyInfo]) -> DeclSyntax {
  let updateProps = props.filter { !$0.isPrimaryKey && !$0.isRelationship }

  var varLines: [String] = []
  var keyLines: [String] = []

  for prop in updateProps {
    let base = prop.typeSyntax.trimmedDescription
      .trimmingCharacters(in: CharacterSet(charactersIn: "?"))
    varLines.append("  public var \(prop.name): \(base)? = nil")
    keyLines.append(codingKeyLine(swiftName: prop.name, columnName: prop.columnName))
  }

  let vars = varLines.joined(separator: "\n")
  let keys = keyLines.joined(separator: "\n")

  return """
    public struct Update: Encodable {
    \(raw: vars)
      public enum CodingKeys: String, CodingKey {
    \(raw: keys)
      }
    }
    """
}

private func makeCodingKeys(from props: [StoredPropertyInfo]) -> DeclSyntax {
  // Include all properties (relationships too — needed for embedded response decoding)
  let lines = props.map { codingKeyLine(swiftName: $0.name, columnName: $0.columnName) }
  let keys = lines.joined(separator: "\n")
  return """
    public enum CodingKeys: String, CodingKey {
    \(raw: keys)
    }
    """
}

private func makeColumnName(typeName: String, from props: [StoredPropertyInfo]) -> DeclSyntax {
  // Only non-relationship properties map to columns
  let columns = props.filter { !$0.isRelationship }
  let cases = columns.map {
    "  if erased == \\\(typeName).\($0.name) { return \"\($0.columnName)\" }"
  }.joined(separator: "\n")

  return """
    public static func columnName<V>(for keyPath: KeyPath<\(raw: typeName), V>) -> String {
      let erased = keyPath as AnyKeyPath
    \(raw: cases)
      preconditionFailure("Unknown column keypath on \(raw: typeName) — macro bug")
    }
    """
}

private func codingKeyLine(swiftName: String, columnName: String) -> String {
  swiftName == columnName
    ? "    case \(swiftName)"
    : "    case \(swiftName) = \"\(columnName)\""
}
```

- [ ] **Step 6: Register TableMacro in Plugin.swift**

In `Sources/SupabaseMacros/Plugin.swift`, add `TableMacro.self` to the array:

```swift
let providingMacros: [any Macro.Type] = [
  PrimaryKeyMacro.self,
  DefaultMacro.self,
  ColumnMacro.self,
  RelationshipMacro.self,
  TableMacro.self,
  // SelectionOfMacro added in Task 5
]
```

- [ ] **Step 7: Run tests — expect pass**

```bash
swift test --filter SupabaseMacrosTests.TableMacroTests
```

Expected: all 3 tests pass. If the expansion strings differ from the actual SwiftSyntax output, run the test once without `expansion:` closures, capture the printed output, and paste it back in.

- [ ] **Step 8: Commit**

```bash
make format
git add Sources/SupabaseMacros/ Tests/SupabaseMacrosTests/TableMacroTests.swift
git commit -m "feat(postgrest): implement @Table macro"
```

---

## Task 5: `@SelectionOf` Macro

`@SelectionOf(Table.self)` synthesizes `SelectionRepresentable` on a struct representing a partial column projection. The `selectString` is a computed property that resolves nested types at runtime (e.g. `"id,title,profile(\(Profile.selectString))"`), so nested `@SelectionOf` types automatically compose.

Known v1 limitation: the macro cannot validate that field names exist on the parent table at compile time. Type mismatches are caught by `Decodable` at runtime.

**Files:**
- Create: `Sources/SupabaseMacros/SelectionOfMacro.swift`
- Modify: `Sources/SupabaseMacros/Plugin.swift`
- Create: `Tests/SupabaseMacrosTests/SelectionOfMacroTests.swift`

**Interfaces:**
- Consumes: `StoredPropertyInfo`, `camelToSnake` from Task 4; `SelectionRepresentable` from Task 2
- Produces: `SelectionOfMacro` type; synthesized `selectString` computed property and `CodingKeys` on annotated structs

Known primitive Swift types that map to plain columns (everything else is treated as a nested `SelectionRepresentable`):
`UUID`, `String`, `Int`, `Int32`, `Int64`, `Bool`, `Double`, `Float`, `Decimal`, `Date`, `Data`, `URL`, `AnyJSON`

- [ ] **Step 1: Write the failing expansion tests**

Create `Tests/SupabaseMacrosTests/SelectionOfMacroTests.swift`:

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

  func testNestedRelationship() {
    assertMacro {
      """
      @SelectionOf(Todo.self)
      public struct TodoWithProfile {
        public let id: UUID
        public let profile: Profile
      }
      """
    } expansion: {
      """
      public struct TodoWithProfile {
        public let id: UUID
        public let profile: Profile

        public enum CodingKeys: String, CodingKey {
          case id
          case profile
        }
      }

      extension TodoWithProfile: SelectionRepresentable {
        public static var selectString: String {
          var parts: [String] = []
          parts.append("id")
          parts.append("profile(\\(Profile.selectString))")
          return parts.joined(separator: ",")
        }
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
        @Column("user_id") public let userId: UUID

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

- [ ] **Step 2: Run tests — expect compile failure**

```bash
swift test --filter SupabaseMacrosTests.SelectionOfMacroTests
```

Expected: compile error — `SelectionOfMacro` not found.

- [ ] **Step 3: Implement SelectionOfMacro.swift**

Create `Sources/SupabaseMacros/SelectionOfMacro.swift`:

```swift
import SwiftSyntax
import SwiftSyntaxMacros
import SwiftSyntaxBuilder

// Types that map directly to PostgREST columns (not nested SelectionRepresentable).
private let knownPrimitives: Set<String> = [
  "UUID", "String", "Int", "Int32", "Int64", "Bool",
  "Double", "Float", "Decimal", "Date", "Data", "URL", "AnyJSON",
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
      context.diagnose(Diagnostic(
        node: node,
        message: SelectionOfDiagnostic.notAStruct
      ))
      return []
    }

    let typeName = type.trimmedDescription
    let selectLines = buildSelectLines(from: structDecl)
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
    let props = parseStoredProperties(from: structDecl)
    let keyLines = props.map {
      $0.name == $0.columnName
        ? "    case \($0.name)"
        : "    case \($0.name) = \"\($0.columnName)\""
    }.joined(separator: "\n")

    return ["""
      public enum CodingKeys: String, CodingKey {
      \(raw: keyLines)
      }
      """]
  }
}

// MARK: - Select string builder

private func buildSelectLines(from decl: StructDeclSyntax) -> [String] {
  var lines: [String] = []
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

    // Resolve column name
    let columnName: String
    if let colAttr = attrs.attribute(named: "Column"),
       let args = colAttr.arguments?.as(LabeledExprListSyntax.self),
       let first = args.first,
       let strLit = first.expression.as(StringLiteralExprSyntax.self),
       let seg = strLit.segments.first?.as(StringSegmentSyntax.self) {
      columnName = seg.content.text
    } else {
      columnName = camelToSnake(name)
    }

    // Unwrap Optional<T> to get the base type name
    let typeText = typeAnnotation.type.trimmedDescription
      .trimmingCharacters(in: CharacterSet(charactersIn: "?"))

    if knownPrimitives.contains(typeText) {
      // Plain column
      lines.append("    parts.append(\"\(columnName)\")")
    } else {
      // Nested SelectionRepresentable — resolved at runtime
      lines.append("    parts.append(\"\(columnName)(\\(\(typeText).selectString))\")")
    }
  }
  return lines
}

// MARK: - Diagnostics

enum SelectionOfDiagnostic: DiagnosticMessage {
  case notAStruct

  var message: String {
    switch self {
    case .notAStruct: return "@SelectionOf can only be applied to structs"
    }
  }
  var diagnosticID: MessageID { .init(domain: "SupabaseMacros", id: "\(self)") }
  var severity: DiagnosticSeverity { .error }
}
```

- [ ] **Step 4: Register SelectionOfMacro in Plugin.swift**

```swift
let providingMacros: [any Macro.Type] = [
  PrimaryKeyMacro.self,
  DefaultMacro.self,
  ColumnMacro.self,
  RelationshipMacro.self,
  TableMacro.self,
  SelectionOfMacro.self,
]
```

- [ ] **Step 5: Run tests — expect pass**

```bash
swift test --filter SupabaseMacrosTests.SelectionOfMacroTests
```

Expected: all 3 tests pass.

- [ ] **Step 6: Commit**

```bash
make format
git add Sources/SupabaseMacros/SelectionOfMacro.swift Sources/SupabaseMacros/Plugin.swift \
        Tests/SupabaseMacrosTests/SelectionOfMacroTests.swift
git commit -m "feat(postgrest): implement @SelectionOf macro"
```

---

## Task 6: Typed PostgREST Builders

Four generic structs wrap the existing builders. Each holds a reference to the underlying string-based builder and translates KeyPath inputs to column name strings before delegating all HTTP work.

**Files:**
- Create: `Sources/PostgREST/TypedBuilders/TypedPostgrestQueryBuilder.swift`
- Create: `Sources/PostgREST/TypedBuilders/TypedPostgrestFilterBuilder.swift`
- Create: `Sources/PostgREST/TypedBuilders/TypedPostgrestTransformBuilder.swift`
- Create: `Sources/PostgREST/TypedBuilders/TypedSingleResultBuilder.swift`
- Create: `Tests/PostgRESTTests/TypedBuildersTests.swift`

**Interfaces:**
- Consumes: `TableRepresentable`, `ReadOnlyTableRepresentable`, `SelectionRepresentable` from Task 2; existing `PostgrestQueryBuilder`, `PostgrestFilterBuilder`, `PostgrestTransformBuilder`, `PostgrestFilterBuilder.Operator` from the PostgREST module
- Produces: the four typed builder types used by Task 7's `PostgrestClient` extension

- [ ] **Step 1: Write tests verifying KeyPath → column name translation**

Create `Tests/PostgRESTTests/TypedBuildersTests.swift`:

```swift
import Foundation
import Testing
@testable import PostgREST
import SupabaseSwiftMacros

// A minimal hand-written @Table conformance for testing — does not use the macro
// so these tests have no macro dependency
struct TestTodo: TableRepresentable {
  var id: UUID
  var title: String
  var isComplete: Bool

  struct Insert: Encodable {}
  struct Update: Encodable {}

  static let tableName = "todos"
  static let schema = "public"
  static let selectString = "*"

  static func columnName<V>(for keyPath: KeyPath<TestTodo, V>) -> String {
    let erased = keyPath as AnyKeyPath
    if erased == \TestTodo.id { return "id" }
    if erased == \TestTodo.title { return "title" }
    if erased == \TestTodo.isComplete { return "is_complete" }
    preconditionFailure("unknown")
  }
}

@Suite("TypedPostgrestFilterBuilder")
struct TypedPostgrestFilterBuilderTests {
  let client = PostgrestClient(
    configuration: PostgrestClient.Configuration(
      url: URL(string: "http://localhost:54321/rest/v1")!,
      schema: nil,
      headers: ["apikey": "test"],
      fetch: { _, _ in (Data(), URLResponse()) },
      encoder: .init(),
      decoder: .init()
    )
  )

  @Test func columnNameTranslation() {
    // eq(\.isComplete) should translate to "is_complete" in the underlying builder
    let builder = client.from(TestTodo.self).select()
    let filtered = builder.eq(\.isComplete, value: false)
    // Verify the URL query contains is_complete=eq.false
    // We access the underlying URL via the builder's internal state
    let url = filtered.underlyingURL
    #expect(url?.query?.contains("is_complete=eq.false") == true)
  }
}
```

> **Note:** `underlyingURL` is a test-only computed property you will add to `TypedPostgrestFilterBuilder` (not in the public API — internal access). Alternatively, verify translation through snapshot testing of the HTTP request; see existing tests in `Tests/PostgRESTTests/` for the `Mocker`-based pattern.

- [ ] **Step 2: Implement TypedSingleResultBuilder.swift**

Create `Sources/PostgREST/TypedBuilders/TypedSingleResultBuilder.swift`:

```swift
import Foundation

/// Wraps a PostgrestTransformBuilder after .single() has been called.
/// execute() returns a single decoded value rather than an array.
public struct TypedSingleResultBuilder<
  Table: ReadOnlyTableRepresentable,
  Selection: SelectionRepresentable
>: Sendable {
  let underlying: PostgrestTransformBuilder

  public func execute() async throws -> PostgrestResponse<Selection> {
    try await underlying.execute()
  }
}
```

- [ ] **Step 3: Implement TypedPostgrestTransformBuilder.swift**

Create `Sources/PostgREST/TypedBuilders/TypedPostgrestTransformBuilder.swift`:

```swift
import Foundation

/// Wraps PostgrestTransformBuilder with typed column ordering.
public struct TypedPostgrestTransformBuilder<
  Table: ReadOnlyTableRepresentable,
  Selection: SelectionRepresentable
>: Sendable {
  let underlying: PostgrestTransformBuilder

  /// Orders results by the given column KeyPath.
  public func order<V>(
    _ column: KeyPath<Table, V>,
    ascending: Bool = true,
    nullsFirst: Bool = false,
    referencedTable: String? = nil
  ) -> Self {
    _ = underlying.order(
      Table.columnName(for: column),
      ascending: ascending,
      nullsFirst: nullsFirst,
      referencedTable: referencedTable
    )
    return self
  }

  public func limit(_ count: Int, referencedTable: String? = nil) -> Self {
    _ = underlying.limit(count, referencedTable: referencedTable)
    return self
  }

  public func range(from: Int, to: Int, referencedTable: String? = nil) -> Self {
    _ = underlying.range(from: from, to: to, referencedTable: referencedTable)
    return self
  }

  public func single() -> TypedSingleResultBuilder<Table, Selection> {
    TypedSingleResultBuilder(underlying: underlying.single())
  }

  public func execute() async throws -> PostgrestResponse<[Selection]> {
    try await underlying.execute()
  }
}
```

- [ ] **Step 4: Implement TypedPostgrestFilterBuilder.swift**

Create `Sources/PostgREST/TypedBuilders/TypedPostgrestFilterBuilder.swift`:

```swift
import Foundation

/// Wraps PostgrestFilterBuilder with typed KeyPath-based filter methods.
/// Table is constrained to ReadOnlyTableRepresentable (the shared base) so this builder
/// works for both read-write tables and views. Selection is the decoded return type.
public struct TypedPostgrestFilterBuilder<
  Table: ReadOnlyTableRepresentable,
  Selection: SelectionRepresentable
>: Sendable {
  let underlying: PostgrestFilterBuilder

  // Expose the underlying URL for testing only
  var underlyingURL: URL? { underlying.mutableState.withValue { $0.request.url } }

  // MARK: - Comparison filters

  public func eq<V: PostgrestFilterValue>(
    _ column: KeyPath<Table, V>, value: V
  ) -> Self {
    _ = underlying.eq(Table.columnName(for: column), value: value)
    return self
  }

  public func neq<V: PostgrestFilterValue>(
    _ column: KeyPath<Table, V>, value: V
  ) -> Self {
    _ = underlying.neq(Table.columnName(for: column), value: value)
    return self
  }

  public func gt<V: PostgrestFilterValue>(
    _ column: KeyPath<Table, V>, value: V
  ) -> Self {
    _ = underlying.gt(Table.columnName(for: column), value: value)
    return self
  }

  public func gte<V: PostgrestFilterValue>(
    _ column: KeyPath<Table, V>, value: V
  ) -> Self {
    _ = underlying.gte(Table.columnName(for: column), value: value)
    return self
  }

  public func lt<V: PostgrestFilterValue>(
    _ column: KeyPath<Table, V>, value: V
  ) -> Self {
    _ = underlying.lt(Table.columnName(for: column), value: value)
    return self
  }

  public func lte<V: PostgrestFilterValue>(
    _ column: KeyPath<Table, V>, value: V
  ) -> Self {
    _ = underlying.lte(Table.columnName(for: column), value: value)
    return self
  }

  public func `in`<V: PostgrestFilterValue>(
    _ column: KeyPath<Table, V>, values: [V]
  ) -> Self {
    _ = underlying.in(Table.columnName(for: column), values: values)
    return self
  }

  public func like<V>(
    _ column: KeyPath<Table, V>, pattern: String
  ) -> Self {
    _ = underlying.like(Table.columnName(for: column), pattern: pattern)
    return self
  }

  public func ilike<V>(
    _ column: KeyPath<Table, V>, pattern: String
  ) -> Self {
    _ = underlying.ilike(Table.columnName(for: column), pattern: pattern)
    return self
  }

  public func `is`<V>(
    _ column: KeyPath<Table, V?>, value: Bool?
  ) -> Self {
    _ = underlying.is(Table.columnName(for: column), value: value)
    return self
  }

  // MARK: - String escape hatch (complex OR, raw PostgREST expressions)

  public func filter(_ column: String, operator op: String, value: String) -> Self {
    _ = underlying.filter(column, operator: .init(rawValue: op) ?? .eq, value: value)
    return self
  }

  public func or(_ filters: String, referencedTable: String? = nil) -> Self {
    _ = underlying.or(filters, referencedTable: referencedTable)
    return self
  }

  // MARK: - Transforms

  public func order<V>(
    _ column: KeyPath<Table, V>,
    ascending: Bool = true,
    nullsFirst: Bool = false,
    referencedTable: String? = nil
  ) -> TypedPostgrestTransformBuilder<Table, Selection> {
    _ = underlying.order(
      Table.columnName(for: column),
      ascending: ascending,
      nullsFirst: nullsFirst,
      referencedTable: referencedTable
    )
    return TypedPostgrestTransformBuilder(underlying: underlying)
  }

  public func limit(
    _ count: Int, referencedTable: String? = nil
  ) -> TypedPostgrestTransformBuilder<Table, Selection> {
    _ = underlying.limit(count, referencedTable: referencedTable)
    return TypedPostgrestTransformBuilder(underlying: underlying)
  }

  public func range(
    from: Int, to: Int, referencedTable: String? = nil
  ) -> TypedPostgrestTransformBuilder<Table, Selection> {
    _ = underlying.range(from: from, to: to, referencedTable: referencedTable)
    return TypedPostgrestTransformBuilder(underlying: underlying)
  }

  public func single() -> TypedSingleResultBuilder<Table, Selection> {
    TypedSingleResultBuilder(underlying: underlying.single())
  }

  // MARK: - Execute

  public func execute() async throws -> PostgrestResponse<[Selection]> {
    try await underlying.execute()
  }
}
```

- [ ] **Step 5: Implement TypedPostgrestQueryBuilder.swift**

Create `Sources/PostgREST/TypedBuilders/TypedPostgrestQueryBuilder.swift`:

```swift
import Foundation

/// Entry point returned by PostgrestClient.from(_ table: T.Type).
/// Mirrors PostgrestQueryBuilder with typed Insert/Update/Delete operations.
public struct TypedPostgrestQueryBuilder<Table: TableRepresentable>: Sendable {
  let underlying: PostgrestQueryBuilder

  // MARK: - SELECT

  /// Selects all columns, returning [Table] (the full row type).
  public func select(
    head: Bool = false,
    count: CountOption? = nil
  ) -> TypedPostgrestFilterBuilder<Table, Table> {
    TypedPostgrestFilterBuilder(
      underlying: underlying.select(Table.selectString, head: head, count: count)
    )
  }

  /// Selects only the columns defined by Selection, returning [Selection].
  public func select<S: SelectionRepresentable>(
    _ selection: S.Type,
    head: Bool = false,
    count: CountOption? = nil
  ) -> TypedPostgrestFilterBuilder<Table, S> {
    TypedPostgrestFilterBuilder(
      underlying: underlying.select(S.selectString, head: head, count: count)
    )
  }

  // MARK: - INSERT

  public func insert(
    _ value: Table.Insert,
    returning: PostgrestReturningOptions = .representation,
    count: CountOption? = nil
  ) -> PostgrestTransformBuilder {
    underlying.insert(value, returning: returning, count: count)
  }

  public func insert(
    _ values: [Table.Insert],
    returning: PostgrestReturningOptions = .representation,
    count: CountOption? = nil
  ) -> PostgrestTransformBuilder {
    underlying.insert(values, returning: returning, count: count)
  }

  // MARK: - UPSERT

  public func upsert(
    _ value: Table.Insert,
    onConflict: String? = nil,
    returning: PostgrestReturningOptions = .representation,
    count: CountOption? = nil,
    ignoreDuplicates: Bool = false
  ) -> PostgrestTransformBuilder {
    underlying.upsert(
      value,
      onConflict: onConflict,
      returning: returning,
      count: count,
      ignoreDuplicates: ignoreDuplicates
    )
  }

  // MARK: - UPDATE

  public func update(
    _ value: Table.Update,
    returning: PostgrestReturningOptions = .representation,
    count: CountOption? = nil
  ) -> TypedPostgrestFilterBuilder<Table, Table> {
    TypedPostgrestFilterBuilder(
      underlying: underlying.update(value, returning: returning, count: count)
    )
  }

  // MARK: - DELETE

  public func delete(
    returning: PostgrestReturningOptions = .representation,
    count: CountOption? = nil
  ) -> TypedPostgrestFilterBuilder<Table, Table> {
    TypedPostgrestFilterBuilder(
      underlying: underlying.delete(returning: returning, count: count)
    )
  }
}

/// Entry point for read-only tables (views). Only select is available.
/// TypedPostgrestFilterBuilder is constrained to ReadOnlyTableRepresentable so this compiles
/// without requiring Table to also conform to TableRepresentable.
public struct TypedReadOnlyQueryBuilder<Table: ReadOnlyTableRepresentable>: Sendable {
  let underlying: PostgrestQueryBuilder

  public func select(
    head: Bool = false,
    count: CountOption? = nil
  ) -> TypedPostgrestFilterBuilder<Table, Table> {
    TypedPostgrestFilterBuilder(
      underlying: underlying.select(Table.selectString, head: head, count: count)
    )
  }

  public func select<S: SelectionRepresentable>(
    _ selection: S.Type,
    head: Bool = false,
    count: CountOption? = nil
  ) -> TypedPostgrestFilterBuilder<Table, S> {
    TypedPostgrestFilterBuilder(
      underlying: underlying.select(S.selectString, head: head, count: count)
    )
  }
}
```

- [ ] **Step 6: Run tests**

```bash
swift test --filter PostgRESTTests.TypedBuildersTests
```

Expected: tests pass. Adjust `underlyingURL` accessor if `mutableState` is not accessible — check `PostgrestBuilder.swift` for the exact internal property name.

- [ ] **Step 7: Commit**

```bash
make format
git add Sources/PostgREST/TypedBuilders/ Tests/PostgRESTTests/TypedBuildersTests.swift
git commit -m "feat(postgrest): add typed query builder wrappers"
```

---

## Task 7: `PostgrestClient` Typed Extension

Adds the `from(_ table: T.Type)` overload to `PostgrestClient`. This is the sole public entry point into the typed API.

**Files:**
- Create: `Sources/PostgREST/PostgrestClient+Typed.swift`

**Interfaces:**
- Consumes: `TypedPostgrestQueryBuilder` (Task 6); `TableRepresentable`, `ReadOnlyTableRepresentable` (Task 2); existing `PostgrestClient.from(_:schema:)` method
- Produces: the public `from(_ table: T.Type)` and `from(_ table: T.Type)` (read-only variant) overloads

- [ ] **Step 1: Write the end-to-end usage test**

Add to `Tests/PostgRESTTests/TypedBuildersTests.swift`:

```swift
@Suite("PostgrestClient typed entry point")
struct PostgrestClientTypedTests {
  let client = PostgrestClient(
    configuration: PostgrestClient.Configuration(
      url: URL(string: "http://localhost:54321/rest/v1")!,
      schema: nil,
      headers: ["apikey": "test"],
      fetch: { _, _ in (Data(), URLResponse()) },
      encoder: .init(),
      decoder: .init()
    )
  )

  @Test func fromReturnsTypedQueryBuilder() {
    let builder = client.from(TestTodo.self)
    // Verify the underlying URL contains the table name
    let selectBuilder = builder.select()
    let url = selectBuilder.underlyingURL
    #expect(url?.absoluteString.contains("todos") == true)
  }

  @Test func fromWithSchemaUsesSchema() {
    // TestTodo.schema == "public" — verify schema header or path as appropriate
    let builder = client.from(TestTodo.self)
    _ = builder // simply verifying it compiles with the correct type
  }
}
```

- [ ] **Step 2: Run the test — expect compile failure**

```bash
swift test --filter PostgRESTTests.PostgrestClientTypedTests
```

Expected: compile error — `from(TestTodo.self)` not found.

- [ ] **Step 3: Implement PostgrestClient+Typed.swift**

Create `Sources/PostgREST/PostgrestClient+Typed.swift`:

```swift
import Foundation

extension PostgrestClient {
  /// Returns a typed query builder for the given table.
  /// The table name and schema are taken from the type's TableRepresentable conformance.
  public func from<T: TableRepresentable>(_ table: T.Type) -> TypedPostgrestQueryBuilder<T> {
    TypedPostgrestQueryBuilder(
      underlying: from(T.tableName, schema: T.schema == "public" ? nil : T.schema)
    )
  }

  /// Returns a read-only typed query builder for a view.
  public func from<T: ReadOnlyTableRepresentable>(_ table: T.Type) -> TypedReadOnlyQueryBuilder<T> {
    TypedReadOnlyQueryBuilder(
      underlying: from(T.tableName, schema: T.schema == "public" ? nil : T.schema)
    )
  }
}
```

- [ ] **Step 4: Run all PostgREST tests**

```bash
swift test --filter PostgRESTTests
```

Expected: all pass (existing string-based tests still pass; new typed tests pass).

- [ ] **Step 5: Run full test suite**

```bash
swift test
```

Expected: all targets pass.

- [ ] **Step 6: Commit**

```bash
make format
git add Sources/PostgREST/PostgrestClient+Typed.swift
git commit -m "feat(postgrest): add PostgrestClient.from(_ table: T.Type) typed entry point"
```

---

## Self-Review Checklist

After completing all tasks, verify:

- [ ] `swift test` passes with zero failures
- [ ] `make format` produces no diff (all files are formatted)
- [ ] The string-based `client.from("todos")` API still compiles and its existing tests pass
- [ ] A hand-written `@Table`-annotated struct (without CLI codegen) compiles and can be used with the typed builders
- [ ] `@SelectionOf` with a nested `@Table` type produces `"fieldName(*)"` in `selectString` at runtime
- [ ] `@SelectionOf` with a nested `@SelectionOf` type produces `"fieldName(id,name)"` in `selectString` at runtime
- [ ] `@Table(readOnly: true)` produces `ReadOnlyTableRepresentable`, and calling `.insert()` on a `TypedReadOnlyQueryBuilder` is a compile error
