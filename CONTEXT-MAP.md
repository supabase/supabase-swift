# Context Map

`supabase-swift` ships one module per Supabase service. Each module is an independent
context with its own vocabulary, and the `Supabase` module is a facade that re-exports
all of them.

## Contexts

- [PostgREST](./Sources/PostgREST/CONTEXT.md) — reads and writes data exposed over PostgREST
- Auth — not yet documented
- Functions — not yet documented
- Realtime — not yet documented
- Storage — not yet documented

`Helpers` is not a context. It holds types shared across contexts (HTTP layer, `AnyJSON`,
wire models, logging) and has no vocabulary of its own.

## Relationships

- **Supabase → every context**: `Supabase` re-exports all contexts with `@_exported import`.
  Every public top-level name in any context is therefore visible to users of every other
  one. This is why contexts prefix their public type names rather than using bare words —
  `Column` is already claimed by Realtime.
- **PostgREST ↔ Realtime**: both describe Postgres tables, columns and row payloads, with
  independently chosen vocabularies. The same user struct may be used by both.
- **Auth → PostgREST**: Auth supplies the access token PostgREST sends for row-level
  security. PostgREST never inspects it.
- **PostgREST → Helpers**: the server error body model and the HTTP request/response types
  are shared, not PostgREST-owned.
