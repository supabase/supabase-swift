---
name: swift-docc
description: >
  Use when adding triple-slash comments to Swift types, methods, or properties; creating a .docc
  catalog folder; writing articles or extension files for a Swift package; fixing DocC build
  warnings about broken symbol links or missing documentation; or setting up module-level
  documentation for the first time.
---

# Swift DocC Documentation

DocC compiles `///` comments and `.docc` catalog files into a navigable **hierarchy**: landing
page → articles → symbol pages. A `## Topics` group is what places a symbol in that hierarchy —
without it, DocC renders the symbol but nothing links to it from the navigation tree.

## Step 1: Identify the scope

| What the user wants | Output to produce |
|---|---|
| Document one symbol | `///` block in the source file |
| Organize many symbols under a type | `///` block on the type with `## Topics` |
| Add Topics without touching source | Extension `.md` file in the catalog |
| Module overview or conceptual guide | `.docc` catalog with a landing page article |
| Step-by-step walkthrough | `.tutorial` file — see [tutorials.md](tutorials.md) |

Completion criterion: you know which output type(s) you will produce before writing anything.

## Step 2: Write symbol documentation

Use `///` (triple-slash only — never `/** */`). The comment must be **directly adjacent** to the
declaration with no blank line between them.

```swift
/// One-sentence abstract describing what this does.
///
/// Extended discussion — one or more paragraphs. Markdown works here:
/// **bold**, _italic_, `inline code`.
///
/// > Note: Appears as a blue callout. Also: Warning, Important, Tip, Experiment.
///
/// Link symbols with double backticks: ``OtherType`` or ``OtherType/method(_:)``.
/// Link articles with: <doc:ArticleName>.
///
/// ```swift
/// let result = try client.fetch(request)
/// ```
///
/// - Parameters:
///   - paramName: What this parameter represents.
///   - another: Another parameter.
/// - Returns: What the return value represents (omit if obvious from the abstract).
/// - Throws: ``MyError/notFound`` when the resource does not exist.
public func fetch(_ request: Request) throws -> Response { ... }
```

**Rules:**
- Abstract is the first non-blank `///` line. It appears in every reference to this symbol.
- `- Parameters:` children are indented two spaces: `  - name: description`.
- `- Returns:` only when the return value adds information beyond the abstract.
- `- Throws:` only when the method can throw. List each error case.
- Properties and enum cases need only the abstract — skip Parameters/Returns.
- No `@param`, `@return`, `@throws` — those are Objective-C javadoc style.

Completion criterion: every public symbol in scope has an abstract; methods with parameters
have a `- Parameters:` block; all thrown errors are listed under `- Throws:`.

## Step 3: Add Topics to build the hierarchy

Without a `## Topics` section, a type's members appear on its page but are not surfaced in the
navigation sidebar or article links. Write Topics either inline in the source or in an extension file.

**Inline (on the type itself):**
```swift
/// The main networking client.
///
/// ## Topics
///
/// ### Creating a Client
/// - ``init(configuration:)``
///
/// ### Making Requests
/// - ``fetch(_:)``
/// - ``upload(_:data:)``
public struct NetworkClient { ... }
```

**Extension file** (`NetworkClient.md` in the `.docc` catalog):
```markdown
# ``NetworkClient``

@Metadata {
  @DocumentationExtension(mergeBehavior: append)
}

## Topics

### Creating a Client
- ``init(configuration:)``

### Making Requests
- ``fetch(_:)``
- ``upload(_:data:)``
```

`mergeBehavior: append` adds the Topics without touching the in-source summary.
`mergeBehavior: override` replaces the in-source documentation entirely.

Completion criterion: every type that owns child symbols has a `## Topics` section listing all
public members under named groups.

## Step 4: Create a documentation catalog (when needed)

A catalog is a folder `ModuleName.docc` placed inside `Sources/ModuleName/`:

```
Sources/Auth/Auth.docc/
├── Auth.md        ← landing page
└── Resources/     ← images, videos (optional)
```

**Landing page (`Auth.md`):**
```markdown
# Auth

@Metadata {
  @TechnologyRoot
}

One-sentence module summary.

## Overview

One or more paragraphs introducing the module.

## Topics

### Essentials
- ``AuthClient``
- ``AuthClientConfiguration``

### Session Management
- ``Session``
- ``User``
```

`@TechnologyRoot` marks this as the module root. Without it, DocC may not render it as a
top-level entry point in Xcode or the web output.

Completion criterion: the catalog folder exists and the landing page compiles without warnings.

## Step 5: Verify

```bash
make test-docs
```

If `make test-docs` is unavailable:
```bash
swift package generate-documentation --target ModuleName 2>&1 | grep -E "warning:|error:"
```

Fix every warning before declaring done.

Completion criterion: the documentation build exits 0 with no warnings.

---

## Common mistakes

| Mistake | Fix |
|---|---|
| Using `/** */` instead of `///` | Replace with triple-slash on every line |
| Blank line between comment and declaration | Remove it — no gap allowed |
| `@param`, `@return`, `@throws` (Obj-C style) | Use `- Parameters:`, `- Returns:`, `- Throws:` |
| Single backticks for symbol links: `` `Foo` `` | Use double backticks: `` ``Foo`` `` |
| Symbol not showing in navigation sidebar | Add a `## Topics` entry linking to it |
| `@TechnologyRoot` missing from landing page | Add `@Metadata { @TechnologyRoot }` |
| Extension file heading uses plain text: `# NetworkClient` | Use symbol path: `` # ``NetworkClient`` `` |
| `doc:Article` link not resolving | Check the article filename matches exactly (case-sensitive) |

---

## Metadata directives reference

| Directive | Purpose |
|---|---|
| `@TechnologyRoot` | Marks the landing page as the module root |
| `@DocumentationExtension(mergeBehavior: append)` | Adds to existing symbol docs |
| `@DocumentationExtension(mergeBehavior: override)` | Replaces existing symbol docs |
| `@DisplayName("Custom Name")` | Overrides how the symbol name renders in navigation |
| `@PageKind(sampleCode)` | Marks a page as sample code |

## Symbol link path syntax

```
``TypeName``
``TypeName/propertyName``
``TypeName/methodName()``
``TypeName/methodName(_:secondLabel:)``
``TypeName/init(label:)``
```
