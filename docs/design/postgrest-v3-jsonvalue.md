# PostgREST v3 — `JSONValue` on the typed `json`/`jsonb` surface

<!-- cspell:words daterange inet macaddr numrange timetz tsrange tstzrange -->

Recommendation for [SDK-1651](https://linear.app/supabase/issue/SDK-1651). It covers the four
opportunities the issue lists, which `JSONValue` to build on, and what the typegen should emit for a
`jsonb` column. Every server claim below was measured on a live PostgREST (local native stack,
CLI 2.120.0); the requests and responses are in [Evidence](#evidence).

## Summary

| # | Opportunity | Verdict |
| - | ----------- | ------- |
| 1 | Gate the JSON methods on a JSON column type | **Accept**, as `where Value == JSONValue`, once the typegen gives every other Postgres type its own Swift type |
| 2 | Take a typed operand in `containsJSON`/`containedByJSON` | **Accept**, as `JSONValue` (not `JSONObject`), JSON-encoded |
| 3 | `jsonObject(_:)` returns `JSONValue` | **Accept**, and comparisons on it must JSON-encode the operand |
| 4 | Separate a key from an array index | **Accept**, and always double-quote the key |

- **Which `JSONValue`:** `Helpers.JSONValue`. The `HTTPRuntime` copy no longer exists.
- **Typegen:** `JSONValue` for `json`/`jsonb`, and for nothing else. Every other Postgres type
  gets its own Swift type, so the generated property's type is the column's Postgres type.

> **Revised.** The first version of this document gated the JSON methods on a marker protocol, so
> an app could opt its own `Codable` type for a `jsonb` column in. Review found that the typegen
> also emitted `JSONValue` for every type it could not map — `interval`, `time`, `bytea`, ranges,
> composites. So `JSONValue` could not stand for a JSON column: the gate let `jsonText` compile on
> an `interval` column, and encoding a `JSONValue` operand as JSON would quote a range or `bytea`
> operand, which Postgres rejects. The design below is the one adopted: one Swift type per
> Postgres type, and `JSONValue` reserved for `json`/`jsonb`.

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

## 1. A distinguishing type for JSON columns — accept, as `where Value == JSONValue`

The gap is real. `containsJSON` on a `text` column compiles and fails at run time with `42883`
(measured below). The same is true of `containsJSON` on a `jsonText(_:)` result, which is `text`.

`containsJSON`, `containedByJSON`, `jsonText` and `jsonObject` move to
`where Value == JSONValue`. That gate is only sound if `JSONValue` means `json`/`jsonb`, so it
rests on the typegen change in [Postgres types](#postgres-types-one-swift-type-each): every other
Postgres type gets its own Swift type.

Users do not hand-write `@Table` structs; the typegen writes them. So the property type in a
`@Table` struct is the column's Postgres type, and an app that wants its own `Codable` shape for a
`jsonb` column declares it in `@SelectionOf`, whose column check compares names only. No opt-in
protocol is needed, and the methods stay closed to every other column. Its fallback is `raw(_:)`.

## 2. Typed operand for `containsJSON`/`containedByJSON` — accept, as `JSONValue`

Take `JSONValue`, not `JSONObject`. `cs`/`cd` accept any JSON value, not only objects: on an array
`[10,20,30]`, both `cs.[20]` and `cs.20` match. `JSONValue` covers all of these, and the literal
conformances keep the call site short: `containsJSON(["a": 1])`, `containsJSON([20])`.

The operand must be **JSON-encoded**, not rendered through `PostgrestFilterValue.rawValue`. That
`rawValue` is correct for objects and arrays, but `.string("x")` renders `x`, which is invalid
JSON (`22P02`). Encode the whole value with `JSONEncoder`, sorted keys and unescaped slashes. Only a
non-finite `.double` fails to encode; then send `NaN`, which PostgREST rejects with `22P02`
(measured, also inside `or=(…)`), rather than a valid stand-in such as `null` that would match
other rows.

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
`JSONValue` is compared against a `text` column. Give `PostgrestFilterValue` a `_typedOperand`
requirement that defaults to `rawValue`, and have `JSONValue` implement it with the JSON encoding.
The typed filters send `_typedOperand`, the untyped builder keeps `rawValue`, and the compiler, not
a runtime cast, picks the form. A `JSONValue` operand then only reaches the typed API from a
`json`/`jsonb` expression.

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

Inside the quotes a backslash escapes the next character: `->"q\"t"` reads the key `q"t`, and
`->"b\s"` reads `bs`. So the key escapes `\` and `"` with a backslash (measured in SDK-2205).

## Postgres types: one Swift type each

`JSONValue` is the right generated type for `json`/`jsonb`: the schema has no shape for the
column. It is the wrong type for anything else, which is what the first version of this document
missed. The typegen maps each Postgres type to one Swift type. A dedicated type exists only where it
changes what compiles or how a value is encoded; otherwise the plain Swift type is used. The
dedicated types live in PostgREST, keep the `_` prefix of the typed API, conform to
`PostgrestFilterValue` with the filter-form `rawValue`, and read and write the text form
PostgREST uses.

| Postgres | Swift | Why a dedicated type |
| -------- | ----- | -------------------- |
| `json`, `jsonb` | `JSONValue` | the JSON methods; the JSON operand |
| `int4range`, `int8range` | `_PostgresRange<Int>` | the range filters take only a range of the column's own bound type |
| `numrange` | `_PostgresRange<Decimal>` | as above |
| `tsrange`, `tstzrange`, `daterange` | `_PostgresRange<Date>` | as above |
| `interval` | `_PostgresInterval` | no `like` (`42883`); text not parsed, it depends on `IntervalStyle` |
| `time`, `timetz` | `_PostgresTime` | no `like` (`42883`) |
| `bytea` | `_PostgresBytes` | `Data`, read and written in the `\x…` hex form, not base64 |
| `inet`, `cidr`, `macaddr`, `money`, `xml` | `String` | none needed |
| composites, geometric and other unmapped types | `_PostgresUnmapped` | holds the JSON PostgREST sends; no filters |

The range gate closes the gap this document first called unsolvable: a range filter on a
non-range column, or with a `daterange` operand on an `int4range` column, no longer compiles.

`_PostgresUnmapped` has no comparisons because Postgres has none for these types: `eq` on a
composite is `0A000`, on a `point` `42883`. Note that a JSON path does work on a composite column
(`pair->>currency=eq.USD` matches), but `_PostgresUnmapped` gets no JSON methods; `raw(_:)` reaches
it.

### What the server does, per type

Measured on a live PostgREST with one column of each type
(`Tests/IntegrationTests/supabase/migrations/20261010000000_postgres_values.sql`):

| Type | JSON PostgREST sends | Operand at top level | Quoted (as inside `or=(…)`) |
| ---- | -------------------- | -------------------- | --------------------------- |
| `int4range` | `"[1,10)"`, `"empty"` | `eq.[1,10)`, `cs.[2,3)` | `eq."[1,10)"` at top level is `22P02`; inside `or=(…)` quoted works, bare is `PGRST100` |
| `tsrange` | `"[\"2024-01-01 00:00:00\",…)"` | `ov.[2024-01-15 00:00,2024-01-16 00:00)` | — |
| `daterange` | canonical: `[2024-01-01,2024-01-31]` comes back `[2024-01-01,2024-02-01)` | — | — |
| any range | — | an element operand, `cs.5`, is `22P02` | — |
| `interval` | `"1 day 02:00:00"`, `"-1 days"` | `eq.1 day 02:00:00`, `eq.26:00:00`, `eq.P1DT2H` all match | `eq."1 day 02:00:00"` also matches |
| `time` | `"13:45:00"`, `"00:00:00.5"` | `eq.13:45`, `gt.12:00` | `eq."13:45"` also matches |
| `timetz` | `"13:45:00+02"` | `eq.13:45:00+02`; `eq.11:45:00+00` does not match | — |
| `bytea` | `"\\xdeadbeef"`, `"\\x"` | `eq.\xdeadbeef` (case-insensitive) | `eq."\xdeadbeef"` is `22P02`; `"\\xdeadbeef"` in a group or list works |
| `money` | `"$12.34"`, `"$1,000.00"` | `eq.12.34`, `eq.$12.34`, `gt.100` | — |
| `inet`, `cidr`, `macaddr` | `"192.168.0.1/24"`, … | `eq.` matches; `macaddr` also in `08-00-2b-…` form | — |
| `xml` | `"<a>1</a>"` | `eq.` is `42883` | — |
| composite | `{"amount":1,"currency":"USD"}` | `eq.(1,USD)` is `0A000`; `->>` works | — |
| `point` | `"(1,2)"` | `eq.` is `42883` | — |

`like` on `interval` and on `time` is `42883`. Every text form above, written back in a `PATCH`
body, round-trips (`"PT90M"` reads back as `"01:30:00"`).

One correction to the review finding that started this revision: a quoted interval works
(`eq."1 day"` matches), so the interval case was not itself a failure. A quoted range or `bytea`
is, and so the bug was real.

## Follow-up work

PR-sized pieces, in this order. All change the unreleased `@_spi(Experimental)` surface, so they
should land before the next release.

1. **SDK-2205 — quote JSON path keys and add an `Int` index overload** (item 4, defect 2).
   Merged in supabase/supabase-swift#1498.
2. **SDK-2208 — one Swift type per Postgres type in the typegen**, with the range gate. The base
   of the stack.
3. **SDK-2206 — gate the JSON methods on `where Value == JSONValue` and take a JSON-encoded
   `JSONValue` in `containsJSON`/`containedByJSON`** (items 1 and 2). On SDK-2208.
4. **SDK-2207 — `jsonObject(_:)` returns `JSONValue`, and the typed operand is chosen by the
   `_typedOperand` requirement** (item 3, defect 1). On SDK-2206.

Not planned now: a check in `@SelectionOf` that a property's type can decode the column's
generated type. Today the macro compares column names only, which is what lets an app decode a
`jsonb` column as its own type.

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
