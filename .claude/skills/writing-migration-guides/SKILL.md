---
name: writing-migration-guides
description: >
  Use when a change is a breaking change — a `fix!:`/`feat!:` commit, a `BREAKING CHANGE:`
  footer, or any edit that changes a public API's shape or behavior — and needs an entry in the
  major-version migration guide (`V<N>_MIGRATION.md` and `docs/migrations/v<N>/<Module>.md`).
  Also use when reviewing a PR that has one, to check it against this format.
---

# Writing Migration Guides

The guide describes the **net** change from the last release of the previous major (for v3:
`v2.55.4`) to the code on `main` now. It is not a changelog. A reader (human or coding agent) uses
it once to move an app across the major version.

## Step 1: Confirm it needs an entry

Every breaking change needs one: a renamed or retyped public symbol, a changed default, a changed
error type, an event that fires differently. A deprecation alone does not; it gets an
`@available(*, deprecated, message: ...)` message instead.

Completion criterion: you can name the exact symbol or behavior that changed.

## Step 2: Find the file

For major version `<N>` (the next major above `git tag --sort=-v:refname | head -1`):

```
V<N>_MIGRATION.md                    # overview: how to migrate, module index, changes in every module, SupabaseClient
docs/migrations/v<N>/Auth.md         # one file per module
docs/migrations/v<N>/PostgREST.md
docs/migrations/v<N>/Storage.md
docs/migrations/v<N>/Functions.md
docs/migrations/v<N>/Realtime.md
```

A change in one module goes into that module's file. A change that affects every module goes into
the overview. Leave one-off feature guides such as `docs/migrations/RealtimeV2 Migration Guide.md`
alone.

Completion criterion: you know the exact file path.

## Step 3: Edit the current state, do not append history

Before you write, search the file for the symbol you change. If an entry for it exists, **edit
that entry** so it shows v2 → the new v3 shape. Do not add a second entry that overrides the first.
If your change reverts an earlier v3 change, delete the entry. Every v3 symbol in the file must
exist in `Sources/` after your PR.

Completion criterion: grep for the old and new symbol names finds one entry, and it is current.

## Step 4: Use the format

Each module file has these parts, in this order:

1. `## Silent changes`: a bullet per change that still compiles but behaves differently. Say what
   changed and what to search for. These matter most, because the compiler does not find them.
2. `## Renames and type changes`: a `| v2 | v3 |` table for mechanical changes (renames,
   enum → struct, dropped `get` prefix, `id:` labels, `Codable` → `Decodable`).
3. One `##` per change that a table row cannot explain: a call site that changes shape, a split
   type, a removed overload with a non-obvious replacement. One or two sentences, then one Swift
   block with `// v2` and `// v3` comments. Real, compiling code.
4. `## Experimental APIs` (optional): `@_spi(Experimental)` APIs, briefly.

Everything outside "Silent changes" is a compile error; do not repeat that. Keep it short: no
history, no PR numbers, a "why" only when it helps the reader decide what to do.

Completion criterion: the entry is in the right part, and its v2 code compiles against the last
v`<N-1>` tag.

## Step 5: Cross-link and verify

- A deprecated fallback points its message at the module file:

  ```swift
  @available(*, deprecated, message: "Use X instead. See migration guide: https://github.com/supabase/supabase-swift/blob/main/docs/migrations/v<N>/<Module>.md")
  ```

- Link the guide from the PR description.
- Run `./scripts/spell-check.sh`. Add real project terms to `dictionary.txt`.

Completion criterion: `./scripts/spell-check.sh` passes.

## Common mistakes

| Mistake | Fix |
| --- | --- |
| Appending a new entry that overrides an older one | Edit the older entry to the net result |
| Putting a module change in `V<N>_MIGRATION.md` | Use `docs/migrations/v<N>/<Module>.md` |
| A long "why" paragraph | Cut it, or keep half a sentence |
| A behavior change in the rename table | Put it under "Silent changes" |
| Pseudocode in the code sample | Real Swift from a real call site |
| Renaming `docs/migrations/RealtimeV2 Migration Guide.md` to fit the pattern | Leave feature guides alone |
