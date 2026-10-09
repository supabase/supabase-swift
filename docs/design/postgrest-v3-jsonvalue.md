# PostgREST v3 — `JSONValue` on the typed `json`/`jsonb` surface

Recommendation for [SDK-1651](https://linear.app/supabase/issue/SDK-1651). It covers the four
opportunities the issue lists, which `JSONValue` to build on, and what the typegen should emit for a
`jsonb` column. Every server claim below was measured on a live PostgREST (local native stack,
CLI 2.120.0); the requests and responses are in [Evidence](#evidence).

## Summary

| # | Opportunity | Verdict |
| - | ----------- | ------- |
| 1 | Gate the JSON methods on a JSON column type | **Accept**, with a marker protocol, not `where Value == JSONValue` |
| 2 | Take a typed operand in `containsJSON`/`containedByJSON` | **Accept**, as `JSONValue` (not `JSONObject`), JSON-encoded |
| 3 | `jsonObject(_:)` returns `JSONValue` | **Accept**, and comparisons on it must JSON-encode the operand |
| 4 | Separate a key from an array index | **Accept**, and always double-quote the key |

- **Which `JSONValue`:** `Helpers.JSONValue`. The `HTTPRuntime` copy no longer exists.
- **Typegen:** keep `JSONValue` for `json`/`jsonb`. It is the only type the generator can know.

The code has moved since the issue was filed, so two of its cost notes no longer hold:

- `HTTPRuntime.JSONValue` was deleted in `c401914b` ("delete the unused HTTPRuntime.JSONValue").
  `Sources/Helpers/JSONValue/JSONValue.swift` is the only `JSONValue` in the repository.
- `PostgrestJSONPath` and the three embedded-column shadows are gone. `jsonText(_:)` and
  `jsonObject(_:)` are declared once, on `_PostgrestColumnExpression`, in
  `Sources/PostgREST/Columns/PostgrestDerivedColumn.swift`, and return
  `_PostgrestDerivedExpression`. Item 3 changes one declaration, not four.

## Two defects in the current surface

The measurements found two wrong behaviors that ship today. They raise the priority of items 3
and 4.

1. **A string operand on a `->` path gives a wrong answer or a 400.** The typegen types a `jsonb`
   column as `JSONValue`, and `jsonObject(_:)` keeps the receiver's `Value`. So
   `$0.data.jsonObject("a").eq(.string("1"))` compiles on generated code today. It renders
   `data->a=eq.1`, because `JSONValue.string`'s filter `rawValue` is the bare string. PostgREST
   reads `1` as the JSON number `1`. The filter matches the row where `a` is the number `1` and
   misses the row where `a` is the string `"1"`. A non-numeric string, such as `.string("x")`,
   is a `22P02` error instead. The correct wire form is `eq."1"`.
2. **A key can not be reached when it looks like an index or holds a `.`.** `jsonObject("0")`
   renders `->0`, which is the array index. A text key `"0"` silently reads `null`.
   `jsonObject("a.b")` renders `->a.b`, which is a `PGRST100` parse error. PostgREST reaches both
   keys when the key is double-quoted: `->"0"`, `->"a.b"`.

## Which `JSONValue`

Build on `Helpers.JSONValue`. It is the only one left. It is public, `@_exported` from PostgREST,
in `sdk-compliance.yaml`, and has every `ExpressibleBy*Literal` conformance.

The issue asked whether `.integer` versus a single `.number` changes what a filter sends. It
changes the rendering (`10` versus `10.0`), but not the result. jsonb compares numbers by value:
`value->n=eq.10` and `value->n=eq.10.0` both match `{"n":10}` and `{"n":10.0}`, and
`cs.{"n":3.0}` matches `{"n":3}`. No follow-up is needed here.

## 1. A distinguishing type for JSON columns — accept, as a marker protocol

The gap is real. `containsJSON` on a `text` column compiles and fails at run time with `42883`
(measured below). The same is true of `containsJSON` on a `jsonText(_:)` result, which is `text`.

Do **not** gate on `where Value == JSONValue`. The typegen emits `JSONValue`, but a hand-written
`@Table` can type a `jsonb` column as the app's own `Codable` struct (`var settings: Settings`).
`@Table` copies the property type into `_PostgrestColumn<Root, Settings>`, so an equality gate
takes `containsJSON` and the path methods away from that column. Typing the column as `JSONValue`
to get them back throws away the decode type the caller wants for `select`.

Gate on a marker protocol instead:

```swift
public protocol _PostgrestJSONColumnValue {}
extension JSONValue: _PostgrestJSONColumnValue {}

// An app opts its own decoded shape in with one line:
extension Settings: _PostgrestJSONColumnValue {}
```

`containsJSON`, `containedByJSON`, `jsonText` and `jsonObject` move to
`extension _PostgrestColumnExpression where Value: _PostgrestJSONColumnValue` (the filters on
`_PostgrestFilterableExpression`). Generated code gets the gate with no change to the generator.
A hand-written column of an app type that does not opt in loses the methods, which is the
intended compile error. Its fallback is `raw(_:)`, which already exists.

This adds one public type, against the issue's hope of none. A marker protocol is the smallest
type that answers both open questions: it keeps the caller's decode type and it gates the
operators. Ranges keep no gate, as the issue asks.

## 2. Typed operand for `containsJSON`/`containedByJSON` — accept, as `JSONValue`

Take `JSONValue`, not `JSONObject`. `cs`/`cd` accept any JSON value, not only objects: on an array
`[10,20,30]`, both `cs.[20]` and `cs.20` match. `JSONValue` covers all of these, and the literal
conformances keep the call site short: `containsJSON(["a": 1])`, `containsJSON([20])`.

The operand must be **JSON-encoded**, not rendered through `PostgrestFilterValue.rawValue`. That
`rawValue` is correct for objects and arrays, but `.string("x")` renders `x`, which is invalid
JSON (`22P02`). Encode the whole value with `JSONSerialization` and `.fragmentsAllowed`, in the
same options `JSONObject.rawValue` uses.

Key order does not matter. `cs.{"b":{"c":2},"a":1}` and `cs.{"a":1,"b":{"c":2}}` return the same
row, and a `cd` operand in scrambled order with reordered array members matches. So `.sortedKeys`
is safe. A `cs` operand inside an `or=(…)` group also works with the existing escaping.

## 3. `jsonObject(_:)` returns `JSONValue` — accept, with JSON-encoded comparisons

Return `_PostgrestDerivedExpression<Root, JSONValue, Position>`. That is what `->` produces, and
with item 1 it carries the JSON gate, so a path chains on: `$0.data.jsonObject("b").containsJSON(["c": 2])`
renders `data->b=cs.{"c":2}`, which the server accepts.

The return type alone is not enough. The comparison family (`eq`, `gt`, …) uses
`PostgrestFilterValue.rawValue`, and that gives defect 1 above. Comparisons on a
`JSONValue`-typed expression must JSON-encode the operand, the same as item 2. Do not change
`JSONValue.rawValue` itself: the untyped v2 builder relies on `.string("x")` rendering `x` when a
`JSONValue` is compared against a `text` column. Add a more constrained overload set
(`where Value == JSONValue`) that Swift prefers over the generic one, or a separate operand
encoder on `_PostgrestFilter`. The follow-up chooses.

Numeric comparison stays typed: `.gt(2)` still compiles through `ExpressibleByIntegerLiteral`,
and `data->n=gt.2` matches `10`, while `data->>n=gt.2` (text) does not.

One residual trap is documented, not fixed: jsonb orders across types (a number sorts above a
string), so `value->n=gt."3"` matches `{"n":3}`. The type system can not see the stored type of
a path, so this is a doc note on `jsonObject(_:)`.

## 4. Key versus array index — accept, and always quote the key

Measured on `[10,20,30]` and `{"0":"zero-key"}`:

| Path | Reads |
| ---- | ----- |
| `value->0` | array index 0 (`10`); `null` on the object |
| `value->-1` | last array element (`30`) |
| `value->"0"` | text key `"0"` (`"zero-key"`) |
| `value->'0'` | `null` everywhere — single quotes are part of the key, not quoting |

So the issue's `data->'0'` is not the PostgREST spelling. The key form is double quotes.

Split the path parameter:

- `jsonObject(_ key: String)` and `jsonText(_ key: String)` render `->"key"` / `->>"key"`, always
  quoted. This fixes `"0"` and `"a.b"` (defect 2). `->"n"` reads the same as `->n`, so quoting an
  ordinary key changes nothing.
- `jsonObject(_ index: Int)` and `jsonText(_ index: Int)` render bare `->0` / `->>0`. Negative
  indexes work.

Not measured: how PostgREST escapes a `"` inside a quoted key. The follow-up must test it before
choosing an escape.

## Typegen: is `JSONValue` the right generated type?

Yes. `tools/supabase-typegen/Sources/SupabaseTypegen/Emitter.swift` maps `json` and `jsonb` to
`JSONValue`. The database schema has no shape for a `jsonb` column, so the generator has no better
type to emit. With the marker protocol from item 1, the generated type gets the JSON methods with
no generator change. A caller who wants a decoded shape declares their own selection type, or
hand-writes the column with an opted-in type. No generator change is recommended.

## Follow-up work

Three PR-sized pieces, in this order. All are source-breaking on the unreleased
`@_spi(Experimental)` surface, so they should land before the next release. Each updates
`sdk-compliance.yaml` if it adds or renames a public symbol.

1. **SDK-2205 — quote JSON path keys and add an `Int` index overload** (item 4, defect 2).
   Independent of the others.
2. **SDK-2206 — gate the JSON methods on `_PostgrestJSONColumnValue` and take a JSON-encoded
   `JSONValue` in `containsJSON`/`containedByJSON`** (items 1 and 2).
3. **SDK-2207 — `jsonObject(_:)` returns `JSONValue`, and comparisons on it JSON-encode the
   operand** (item 3, defect 1). Depends on SDK-2206 for the gate.

The issue's acceptance criteria ask for a spec in `supabase/sdk`. This document is the spec for
these pieces instead: the changes are Swift-only, and no other SDK has this typed surface.

## Evidence

Run against `key_value_storage (key text, value jsonb)` from
`Tests/IntegrationTests/supabase/migrations`, with these rows inserted and deleted afterwards. No
migration was added.

```json
[
  {"key":"j1","value":{"a":1,"b":{"c":2},"n":10,"tags":["x","y"]}},
  {"key":"j2","value":{"a":"1","n":2}},
  {"key":"j3","value":[10,20,30]},
  {"key":"j4","value":{"0":"zero-key","n":3,"a.b":"dotted"}},
  {"key":"j5","value":{"n":10.0}}
]
```

Every request also carries `select=key&key=like.j*&order=key`; it is left out below.

### `->>` compares text, `->` compares JSON

```text
value->>n=gt.2       → j4              ("10" < "2" as text)
value->n=gt.2        → j1, j4, j5
value->n=eq.10       → j1, j5
value->n=eq.10.0     → j1, j5          (10 and 10.0 are equal)
value->>n=eq.10      → j1
```

### A string operand on `->`

```text
value->a=eq.1        → j1              (number 1, not the string "1")
value->a=eq."1"      → j2
value->>a=eq.1       → j1, j2
value->b=eq.x        → 400 {"code":"22P02","details":"Token \"x\" is invalid.",
                                "message":"invalid input syntax for type json"}
value->n=gt."3"      → j4              (number 3 sorts above string "3")
```

### Key versus index

```text
select=key,v:value->0     → j3: 10, all others null
select=key,v:value->-1    → j3: 30, all others null
select=key,v:value->'0'   → null for every row
select=key,v:value->"0"   → j4: "zero-key", all others null
select=key,v:value->"n"   → j4: 3
select=key,v:value->"a.b" → j4: "dotted"
select=key,v:value->a.b   → 400 {"code":"PGRST100","message":"\"failed to parse select parameter
                                   (key,v:value->a.b)\" (line 1, column 16)"}
value->0=eq.10            → j3
value->>"0"=eq.zero-key   → j4
value->>'0'=eq.zero-key   → (none)
```

### `cs` / `cd` and key order

```text
value=cs.{"a":1}                                          → j1
value=cs.{"b":{"c":2},"a":1}                              → j1
value=cs.{"a":1,"b":{"c":2}}                              → j1
value=cs.[20]                                             → j3
value=cs.20                                               → j3
value=cs.{"n":10}                                         → j1, j5
value=cs.{"n":3.0}                                        → j4
value=cd.{"z":0,"tags":["y","x"],"n":10,"b":{"c":2},"a":1} → j1, j5
value->b=cs.{"c":2}                                       → j1
or=(value.cs.{"a":1},value.cs.{"n":3})                    → j1, j4
```

### The wrong column

```text
key=cs.{"a":1}       → 400 {"code":"42883","message":"operator does not exist: text @> unknown"}
value->>n=cs.{"a":1} → 400 {"code":"42883","message":"operator does not exist: text @> unknown"}
```
