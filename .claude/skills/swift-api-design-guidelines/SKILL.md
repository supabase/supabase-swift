---
name: swift-api-design-guidelines
description: >
  Use whenever you write, name, or review any public (or internal-but-API-shaped) Swift
  declaration in this repo — a method, function, initializer, property, protocol, or parameter —
  and especially before opening a PR that adds or renames public API. Covers naming clarity,
  argument labels, factory/initializer conventions, boolean and mutating/nonmutating naming, and
  terms of art, per https://www.swift.org/documentation/api-design-guidelines/. Also use when
  reviewing a PR's diff for naming issues, or when the user asks "does this read well",
  "what should I call this", or "is this the Swift-y name". This is the naming/clarity layer;
  AGENTS.md's "Enum-like Values" and "Codable Conformance" sections cover the structural rules
  (RawRepresentable vs enum, which protocols to conform to) — use both together when a change
  touches an enum-like value's shape.
---

# Swift API Design Guidelines

Reference: [swift.org/documentation/api-design-guidelines](https://www.swift.org/documentation/api-design-guidelines/).

The test for every rule below is the same: **read the call site, not the declaration.** A name is
declared once and used many times, so an awkward declaration that reads fine at the use site beats
a tidy declaration that reads badly there. When in doubt, write the call site out and read it as an
English phrase.

## Fundamentals

- Clarity at the point of use outranks brevity. Swift's terseness should come from the type
  system and inference, not from cutting words a reader needs.
- Every public declaration gets a documentation comment (see the `swift-docc` skill for the format
  and building the catalog). If the summary is hard to write in one sentence fragment, the API is
  probably shaped wrong — fix the design before you fix the doc comment.

## Promote Clear Usage

- **Include every word needed to avoid ambiguity at the call site.**
  `remove(at: position)` vs. `remove(position)` — the second reads like "remove the element equal
  to position," which is wrong.
- **Omit words that don't add information**, especially ones that just repeat the type:
  `remove(_ member: Element)` over `removeElement(_ member: Element)` — `allViews.remove(cancelButton)`
  already tells you what's being removed.
- **Name parameters, variables, and associated types after their role, not their type.**
  `func restock(from widgetFactory: WidgetFactory)`, not `func restock(from factory: WidgetFactory)`
  repurposed as if the type name were the role.

## Strive for Fluent Usage

- Prefer names that make the call site read as a grammatical English phrase:
  `x.insert(y, at: z)` ("x, insert y at z"), not `x.insert(y, position: z)`.
- It's fine for fluency to degrade after the first argument or two, once those arguments stop
  being central to the call's meaning (e.g. trailing `options:`/`completionHandler:`).
- **Factory methods start with `make`**: `x.makeIterator()`.
- **The first argument to an initializer or factory method doesn't form a phrase with the base
  name** — don't chase grammatical continuity there:
  ```swift
  let foreground = Color(red: 32, green: 64, blue: 128)      // good
  let foreground = Color(havingRGBValuesRed: 32, ...)        // no — forcing a phrase
  ```
- **Boolean methods and properties read as assertions about the receiver**: `x.isEmpty`,
  `line1.intersects(line2)`, not `x.empty` or `x.getIntersects(line2)`.
- **Mutating/nonmutating pairs follow the verb/`-ed`-or-`-ing` pattern**, or the `form`- prefix
  when there's no natural participle: `x.sort()` / `x.sorted()`, `x.append(y)` / `x.appending(y)`,
  `x.formUnion(y)` / `x.union(y)`.
- **Protocols that describe what something *is* read as nouns** (`Collection`). **Protocols that
  describe a capability use `-able`/`-ible`/`-ing`** (`Equatable`, `ProgressReporting`).

## Use Terminology Well

- Prefer the common word over the term of art when both convey the meaning — don't say
  "epidermis" for "skin."
- If you do use a term of art, use it exactly as the field already uses it. Don't invent a new
  meaning for an existing term; an expert reader will trust the familiar meaning and be misled.
- Avoid abbreviations, especially non-standard ones — they're terms of art too, understandable
  only if the reader can guess the expansion.
- Embrace precedent: reuse names and patterns the standard library and Apple frameworks already
  established (`Sequence`, `map`, `flatMap`) instead of inventing parallel vocabulary.

## General Conventions

- Document the complexity of any computed property that isn't O(1) — callers assume property
  access is free.
- Prefer methods and properties to free functions. Free functions are for the cases with no
  obvious `self` (`min(x, y)`), unconstrained generics (`print(x)`), or established math notation
  (`sin(x)`).
- Case conventions: types and protocols are `UpperCamelCase`, everything else `lowerCamelCase`.
  Acronyms that are conventionally all-caps stay all-caps as a unit (`utf8Bytes`, `userSMTPServer`);
  other acronyms are treated as ordinary words (`radarDetector`).

## Parameters

- Choose parameter names for how they read in the generated documentation, not just at the call
  site — `filter(_ predicate: ...)` documents naturally as "elements that satisfy `predicate`";
  `filter(_ includedInResult: ...)` doesn't.
- Give a parameter a default when one value is overwhelmingly common — it simplifies the call site
  for the typical case without losing the explicit form for the rest.

## Argument Labels

```swift
func move(from start: Point, to end: Point)
x.move(from: x, to: y)
```

- Omit all labels when arguments can't be usefully distinguished: `min(number1, number2)`,
  `zip(sequence1, sequence2)`.
- In an initializer that performs a **value-preserving type conversion**, omit the first label —
  the source type is already the whole story: `String(veryLargeNumber)`. In a **narrowing**
  conversion, label the narrowing: `UInt32(truncating: someUInt64)`,
  `UInt32(saturating: someUInt64)`.
- If the first argument forms part of a prepositional phrase, label it starting at the
  preposition, with the label itself beginning right after that preposition:
  `a.moveTo(x: b, y: c)`, `a.fadeFrom(red: b, green: c, blue: d)`.
- Otherwise, if the first argument is part of a grammatical phrase, omit its label and fold any
  preceding words into the base name: `x.addSubview(y)`. If it *isn't* part of a phrase, it needs
  a label: `view.dismiss(animated: false)`.

## Special Instructions

- Label tuple members and name closure parameters wherever they appear in your API — those names
  carry explanatory power and can be referenced from doc comments, even though closure-parameter
  labels aren't visible at the call site.
- Take extra care with unconstrained polymorphism (`Any`, `AnyObject`, unconstrained generics) —
  it's easy to create ambiguous overloads that only differ under the hood.

---

## Common mistakes

| Mistake | Fix |
|---|---|
| `removeElement(_:)` | `remove(_:)` — the type name in the method name is redundant with the call site |
| `remove(x)` for "remove at position x" | `remove(at: x)` — bare noun implies value-equality removal |
| `Color(havingRGBValuesRed:green:andBlue:)` | `Color(red:green:blue:)` — don't force initializer args into a phrase with the base name |
| `x.getIntersects(y)` / `x.empty` | `x.intersects(y)` / `x.isEmpty` — booleans read as assertions |
| `x.sort()` returning a new array | `x.sorted()` for the nonmutating form; `sort()` implies mutation |
| A capability protocol named as an adjective-less noun, e.g. `Progress` for something reporting progress | `ProgressReporting` — capability protocols take `-able`/`-ible`/`-ing` |
| A free function where a method would do (`describe(x)`) | Make it a method (`x.describe()`) unless there's no obvious `self` |
| Abbreviated parameter name (`fn`, `cfg`) | Full word (`function`, `configuration`) — abbreviations are terms of art |
