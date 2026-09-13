# Legacy

These files are the API this package shipped before the value-typed core. They are deprecated in
stage 4 and deleted in the next major. They are **behaviorally frozen**: do not fix bugs here, do
not reimplement them over the new core.

Spec §6 explains why — today's builders carry their own retry loop and inconsistent escaping, and
silently changing that mid-deprecation is exactly what deprecating something is meant to avoid. The
spec lives on the `docs/postgrest-v3-design` branch, at `docs/design/postgrest-v3.md`.

## The typed API still leans on this directory

Frozen does not yet mean unreferenced. `Query/` currently builds on symbols declared here:

| Symbol | Declared in | Replaced by |
| --- | --- | --- |
| `PostgrestRequestBuilder` | `PostgrestRequestBuilder.swift` | `HTTPRuntime`'s `HTTPRequestBuilder` (stage 2 task 2) |
| `PostgrestQueryPhase`, `PostgrestFilterPhase`, `PostgrestTransformPhase` and their protocols | `PostgrestRequestBuilder.swift` | kept — the phase markers are shared, not legacy |
| `PostgrestResponse` | `Types.swift` | a new `PostgrestResponse` (stage 2 task 4) |
| `PostgrestClient` | `PostgrestClient.swift` | the wire client (stage 2 task 10) |

That dependency is temporary and one-way. Stage 2 task 7 rebuilds the typed wrappers on
`HTTPRuntime`'s request model, which is when this directory becomes genuinely standalone. Until then, a change
here can still break `Query/` — which is another reason not to make one.
