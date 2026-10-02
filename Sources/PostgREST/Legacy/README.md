# Legacy

These files are the API this package shipped before the value-typed core. They are deprecated in
stage 4 and deleted in the next major. They are **behaviorally frozen**: do not fix bugs here, do
not reimplement them over the new core.

Spec §6 explains why — today's builders carry their own retry loop and inconsistent escaping, and
silently changing that mid-deprecation is exactly what deprecating something is meant to avoid. The
spec lives on the `docs/postgrest-v3-design` branch, at `docs/design/postgrest-v3.md`.

## The typed API still leans on this directory

Frozen does not yet mean unreferenced. `Query/` and `Request/` no longer hold a
`PostgrestRequestBuilder` (SDK-1568), but they still build on these symbols declared here:

| Symbol | Declared in | Replaced by |
| --- | --- | --- |
| `PostgrestResponse`, `CountOption`, `ExplainFormat` | `Types.swift` | a new `PostgrestResponse` (stage 2 task 4) |
| `PostgrestClient`, its `Configuration.retryPolicy` and `HTTPField.Name.prefer` | `PostgrestClient.swift` | the wire client (stage 2 task 10) |
| `HTTPField.Name.acceptProfile`, `.contentProfile` | `PostgrestRequestBuilder.swift` | the wire client (stage 2 task 10) |

That dependency is temporary and one-way. Until it is gone, a change here can still break `Query/`
— which is another reason not to make one.
