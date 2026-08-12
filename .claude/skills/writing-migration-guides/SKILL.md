---
name: writing-migration-guides
description: >
  Use when a change is a breaking change — a `fix!:`/`feat!:` commit, a `BREAKING CHANGE:`
  footer, or any edit that changes a public API's shape or behavior — and needs an entry in
  docs/migrations/. Also use when reviewing a PR that has one, to check it against this format.
---

# Writing Migration Guides

Reference: [supabase-flutter's MIGRATION.md](https://github.com/supabase/supabase-flutter/blob/main/MIGRATION.md).
It gets this right — read a section or two before writing your own if you want the tone.

## Step 1: Confirm it needs an entry

Every breaking change needs one: a renamed or retyped public symbol, a changed default, a changed
error type, an event that fires differently, anything that a `feat!:`/`fix!:` commit or
`BREAKING CHANGE:` footer would announce. A deprecation alone does not — that gets an
`@available(*, deprecated, ...)` message instead (see Step 5).

Completion criterion: you can name the exact symbol or behavior that changed and why a caller
would need to touch their code because of it.

## Step 2: Find the file, don't create a new one

supabase-swift keeps one migration guide **per module per upcoming major version**, not one per
change:

```
docs/migrations/<Module> V<N> Migration Guide.md
```

`<Module>` is the target's module name (`Auth`, `Storage`, `Realtime`, ...). `<N>` is the next
major version above the latest release tag — check it with `git tag --sort=-v:refname | head -1`;
if the latest tag is `v2.55.0`, `<N>` is `3`.

If the file for this module and version already exists (because someone already landed a breaking
change for the upcoming major release), append a new `##` section to it. Only create a new file
when none exists yet for that module/version pair.

This is unrelated to one-off feature-migration guides like `RealtimeV2 Migration Guide.md`, which
document moving from an old API to a new parallel one, not a version bump — leave those as they are.

Completion criterion: you know the exact file path, and whether you are creating it or appending
to it.

## Step 3: Write the section

Give the section a `##` heading naming the exact symbol or behavior, in backticks:

```markdown
## `AuthResponse.user` is now optional
```

Then, in order:

1. **What changed.** One or two sentences. Name the concrete types/names involved — not "the API
   changed" but "`AuthResponse.user` is `User?` instead of `User`".
2. **Why.** The concrete cause: a bug that surfaced, a shape the server actually sends, an
   inconsistency with another Supabase SDK. Never "for consistency" or "to improve the API" on
   their own — say what broke or what it now matches.
3. **Before/After code.** Real call-site Swift, not pseudocode:

   ```swift
   // Before
   let email = response.user.email

   // After
   let email = response.user?.email
   ```
4. **Compile error or silent?** State this explicitly. If the change is a type change that Swift's
   compiler will catch (like the example above), say so — the reader can grep for the compiler's
   error list. If it is a behavior change that still compiles (a default flipping, an event firing
   under a different name), say so too, and tell the reader what to search their codebase for.
5. **Escape hatch, if any.** If the old behavior is still reachable (an explicit parameter, a
   different call), show it.

When a change enumerates more than two or three renames or replacements, use a table instead of
prose:

```markdown
| Before | After |
| --- | --- |
| `RealtimeClient.conn` | `RealtimeClient.connection` |
| `RealtimeClient.connState` | `RealtimeClient.connectionState` |
```

Completion criterion: the section has What/Why/Before-After, and explicitly says whether the
break is a compile error.

## Step 4: Order and grouping within the file

If the file already has sections for other changes targeting the same version, add yours as a new
`##` section rather than folding it into an existing one, even if the topic feels related. One
section per distinct breaking change keeps each one independently linkable.

## Step 5: Cross-link and verify

- Link the guide from the PR description.
- If this breaking change comes with a deprecated fallback (the old API keeps working but is
  marked `@available(*, deprecated, ...)`), point its message at the guide using the pattern
  already used in `Sources/Realtime/Deprecated/*.swift`:

  ```swift
  @available(*, deprecated, message: "Use X instead. See migration guide: https://github.com/supabase-community/supabase-swift/blob/main/docs/migrations/<Module>%20V<N>%20Migration%20Guide.md")
  ```

- Run `./scripts/spell-check.sh` — migration guides are Markdown and get spell-checked with
  everything else. Add project-specific terms to `dictionary.txt` if it flags something legitimate.

Completion criterion: `./scripts/spell-check.sh` passes, and the guide is named in the PR
description.

---

## Common mistakes

| Mistake | Fix |
|---|---|
| Creating a new file per breaking change | Append a `##` section to the existing `<Module> V<N> Migration Guide.md` |
| "For consistency" / "to improve the API" as the whole reason | Name the concrete cause: a bug, a server behavior, a mismatch with another SDK |
| Pseudocode in Before/After | Use real, compiling Swift from an actual call site |
| Not saying whether it's a compile error | Always call it out — readers need to know whether their build will catch it or not |
| Prose listing many renames | Use a `\| Before \| After \|` table |
| Renaming an unrelated one-off guide (e.g. `RealtimeV2 Migration Guide.md`) to fit the `<Module> V<N>` pattern | Leave feature-migration guides alone; the versioned pattern is only for major-version breaking changes |
