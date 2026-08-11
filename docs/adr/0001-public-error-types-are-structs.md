---
status: accepted
---

# Public error types are structs with an extensible kind, not enums

`scripts/build-for-library-evolution.sh` builds the package with
`-enable-library-evolution`, which makes adding a case to a public enum a **binary**-breaking
change for resilient clients, not merely a source-breaking one for exhaustive `switch`
statements. Every new failure mode we discover would therefore require a major version. So
public error types are structs carrying a `kind` property, where the kind is a
`RawRepresentable` struct with static members rather than an enum — the same idiom
`ExplainFormat` already uses in `Sources/PostgREST/Types.swift`.

## Consequences

Callers cannot `switch` exhaustively over failure modes and get compiler-enforced
completeness; they compare against known kinds and need a fallback branch. We accept that
cost because the alternative is a major version bump every time the server grows a new error
condition. Adding a kind is then additive, and existing code keeps compiling and running.
