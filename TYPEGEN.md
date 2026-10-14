# The typegen tool

`tools/supabase-typegen` is a separate SwiftPM package holding the `supabase-typegen` executable,
which turns a `GeneratorMetadata` document into `@Table` structs. It is not part of the root
package on purpose: SwiftPM fetches the dependencies of every product a package vends, so its
swift-format dependency would reach every app that depends on `Supabase` and pin their
swift-syntax to one major. Its `CamelToSnake.swift` is a symlink to the `@Table` macro's source, so
the generator decides `@Column` with the macro's own function.

```bash
swift build --package-path tools/supabase-typegen
swift test --package-path tools/supabase-typegen

# Rewrite the golden files after an intended change
SUPABASE_TYPEGEN_RECORD=1 swift test --package-path tools/supabase-typegen --filter EmitterTests
```

Three of the goldens are the `Generated.swift` sources of root test targets
(`SupabaseTypegenOutputTests`, `SupabaseTypegenPostgrestTypegenOutputTests`,
`SupabaseTypegenHostileOutputTests`), built with `-enable-library-evolution` on Apple platforms
only, because Linux's Foundation is not built with library evolution. On Darwin the build prints
warnings that `PostgrestMacros` was not compiled with library evolution; they are expected. The
macOS CI jobs compile the generated code with library evolution; the Linux job runs the same
behavioral tests without it. A change to the macros or to `PostgREST` that breaks generated code
fails `swift test` at the root; a generator change that is not recorded fails `EmitterTests`.
`SupabaseTypegenOutputTests` also runs queries through the generated types. `IntegrationTests`
compiles the same file through the symlink `Tests/IntegrationTests/Postgrest/Generated.swift` (a
test target cannot depend on another), so the Postgrest integration tests query the integration
schema with its generated models. After changing a migration there, refresh the fixtures and record
the goldens.

A Postgres enum becomes a Swift `enum` (`String, Codable, Hashable, Sendable,
PostgrestFilterValue`), generated for every enum in a selected schema and for any other enum a
generated column uses. "Enum-like Values" in [CODE_STYLE.md](CODE_STYLE.md) governs the SDK's own types, not this generated code: a
label added to the Postgres enum fails to decode until the user regenerates.

Each Postgres type maps to one Swift type, so the generated `@Table` property's type is the column's
Postgres type. An app that decodes a column as its own type declares it in `@SelectionOf`. A type
with no plain Swift counterpart gets one of PostgREST's `_Postgres…` types (in
`Sources/PostgREST/Columns/PostgresValueTypes.swift`) when that changes what compiles or how a
value is encoded, and a plain Swift type otherwise:

| Postgres | Swift |
| -------- | ----- |
| `json`, `jsonb` | `JSONValue`, and nothing else is |
| `int4range`, `int8range` / `numrange` / `tsrange`, `tstzrange`, `daterange` | `_PostgresRange<Int>` / `<Decimal>` / `<Date>`, the only type the range filters accept |
| `interval` | `_PostgresInterval`, the text PostgREST sends, not parsed (it depends on `IntervalStyle`) |
| `time`, `timetz` | `_PostgresTime` |
| `bytea` | `_PostgresBytes`, `Data` in the `\x…` hex form, not base64 |
| `inet`, `cidr`, `macaddr`, `money`, `xml` | `String` |
| a composite, a geometric type, an extension type other than `citext` | `_PostgresUnmapped` |

`_PostgresUnmapped` holds whatever JSON PostgREST sends for the column and writes it back
unchanged, so one such column never stops generation, and the generator writes a note naming the
column on standard error. It has no filters: Postgres has no equality for a composite or a `point`.

A Postgres `date` becomes `Date`, read and written as midnight UTC. A caller who builds "today" at
local midnight east of UTC writes the previous day; build the value in a UTC calendar.

Computed fields and relationships come from `functions`: one `extension <Type>.Columns` per
relation, for each function with one input argument of the relation's row type, in the relation's
own schema, and not named like a column (compared as Postgres names). A scalar return type gives
`_PostgrestComputedField` (the mapping above applies); a row type gives `_PostgrestToOneRelation`, or
`_PostgrestToManyRelation` when the function returns a `SETOF` with more than one `ROWS`. A function
that returns `void`, `record`, a set of scalars, or a row type the generator does not emit is
skipped. Each skip, and each rename that a name clash needs, is a note on standard error.

## Releasing the typegen binary

See "Releasing the typegen binary" in [RELEASE.md](RELEASE.md).

## Refreshing the typegen fixtures

`tools/supabase-typegen/Tests/SupabaseTypegenTests/Fixtures` holds `GeneratorMetadata` documents,
the input of the `supabase-typegen` executable. Two come from postgrest-typegen's `introspect` (in
[supabase/sdk](https://github.com/supabase/sdk)): `generator_metadata.json`, from the integration
migrations, and `postgrest_typegen_metadata.json`, from postgrest-typegen's own test fixtures.
`hostile_metadata.json` is hand-written to exercise renames and fallbacks: the script below does not
touch it and `provenance.json` does not describe it. Regenerate the other two after a migration in
`Tests/IntegrationTests/supabase` changes or after updating postgrest-typegen:

```bash
SDK_DIR=~/work/sdk ./scripts/refresh-typegen-fixtures.sh
```

It needs Docker and bun, and starts and removes its own Postgres containers. `provenance.json` next
to the fixtures records the postgrest-typegen version, the supabase/sdk commit and the
`GeneratorMetadata` version they came from.
