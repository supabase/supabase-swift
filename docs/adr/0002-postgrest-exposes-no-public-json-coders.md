---
status: accepted
---

# The PostgREST v3 API exposes no configurable JSON encoder or decoder

The v3 query API derives column names from a row type's `CodingKeys`, so that the columns a
filter targets and the keys an insert body writes can never disagree. A caller-supplied
`JSONEncoder` or `JSONDecoder` breaks that guarantee silently: set
`keyDecodingStrategy = .convertFromSnakeCase` and a type maps `created_at` to `createdAt`
with no `CodingKeys` at all, at which point derived column names are wrong and the generated
`select=createdAt` gets a 400. This is not hypothetical — `Examples/SlackClone/Supabase.swift`
does exactly this today. So the v3 configuration has no coder knobs, and a per-type naming
convention on the declaration generates the `CodingKeys` and the column names together from
one source.

## Considered options

Detecting the contradiction at runtime and reporting an issue in debug builds was rejected:
the failure produces a wrong query rather than an error, and making it unrepresentable is
strictly better than warning about it.

## Consequences

Callers who need `userInfo`-driven decoding or a custom `Data` strategy use the raw escape
hatches — reading the response body as `Data` and decoding it themselves, or supplying a
pre-encoded body. Apps that configured one global snake-case coder must declare the
convention per type instead. The existing `SupabaseClientOptions.DatabaseOptions.encoder` and
`.decoder` stay untouched for the deprecated v1 API.
