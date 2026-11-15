# Contributing

How to make a change: conventions for commits, public API, and the usual workflows.

See [DEVELOPMENT.md](DEVELOPMENT.md) to set up, build, and test, and [CODE_STYLE.md](CODE_STYLE.md) for code conventions.

## Commit Conventions

This project uses [Conventional Commits](https://www.conventionalcommits.org/) with release-please for automated versioning:

- `feat:` - New features (minor version bump)
- `fix:` - Bug fixes (patch version bump)
- `docs:` - Documentation changes
- `test:` - Test changes
- `refactor:` - Code refactoring
- `perf:` - Performance improvements
- `chore:` - Build/tooling changes
- `feat!:` or `BREAKING CHANGE:` - Breaking changes (major version bump)

Example: `feat(auth): add PKCE flow support`

The `!`/`BREAKING CHANGE:` marker is the same one release-please and the API stability check key
off to bump majors and flag reviewers. Every commit carrying it also requires an entry in the
major-version migration guide (`V<N>_MIGRATION.md` and `docs/migrations/v<N>/`) — see the writing-migration-guides skill for the format.

## Capability Compliance

`sdk-compliance.yaml` declares this SDK's public API against the
[supabase/sdk](https://github.com/supabase/sdk) capability matrix.
`.github/workflows/validate-capabilities.yml` calls supabase/sdk's reusable
compliance workflow on every PR, and it does check for both newly added
public API not listed in the manifest and registered symbols the code no
longer has. That workflow is not a required status check on `main`. Only
`CI Success` (this repo's own `ci.yml`) and the WIP/draft gate are. The
"SDK compliance" job in `ci.yml` is part of `CI Success`, and it runs
`./scripts/check-compliance.sh`.

**Any change to public API — adding, removing, renaming, or moving a
symbol — updates `sdk-compliance.yaml` in the same commit.** This includes
symbols a refactor deletes: a stale entry for a symbol that no longer
exists is as much a compliance failure as a missing one. See the file's
own comments and
`https://github.com/supabase/sdk/blob/main/CONTRIBUTING.md` for the
format.

```bash
# Check sdk-compliance.yaml against the current public API
./scripts/check-compliance.sh
```

It needs no network access and no checkout of `supabase/sdk`. It fails when:

- `sdk-compliance.yaml` declares a symbol the public API no longer has.
- The undeclared public symbols differ from `scripts/compliance-baseline.txt`.
  A symbol that is not in the baseline is new public API: declare it. A
  baseline symbol that is now declared means the baseline is out of date:
  run `./scripts/check-compliance.sh --update-baseline` and commit the
  result. An update only removes symbols from the baseline. It never adds
  one.

Only symbols declared under `Sources/` count, minus the files that
`.sdk-parse-ignore` matches. Only Auth still has undeclared symbols
(SDK-2091).

The symbol graph depends on the platform and the SDK. CI runs the check
on macOS with Xcode 27.0, so run it there too. On Linux or another Xcode,
some Apple-only APIs drop out and the check reports false results.

What to declare: a type together with its public `init` and its members.
Do not declare a member without its owning type. Declare every public macro.

### Version strings in docs

Every version string that users copy (the README install snippet,
`V3_MIGRATION.md`, the typegen install snippet, both `Version.swift` files)
sits in a file listed in `release-please-config.json` `extra-files`, with an
`x-release-please-version` marker. The README library list matches the
`.library` products in `Package.swift`.

## Common Tasks

### Adding a New Feature

1. Create feature branch from `main`
2. Implement feature with tests
3. If the feature adds or changes public API, update `sdk-compliance.yaml`
   in the same commit (see "Capability Compliance" above) and run
   `./scripts/check-compliance.sh`
4. Run `./scripts/format.sh` to format code
5. Run `swift test` to verify tests pass
6. Add documentation if needed
7. Create PR with conventional commit title
8. Ensure CI passes

### Fixing a Bug

1. Add a failing test that reproduces the bug
2. Fix the bug
3. If the fix adds, removes, or renames public API, update
   `sdk-compliance.yaml` in the same commit and run
   `./scripts/check-compliance.sh`
4. Verify test now passes
5. Run full test suite
6. Create PR with `fix:` prefix

### Hotfixes for v2

`release/v2` ships v2 patch releases while `main` moves toward v3. Fix a bug on `main` first, then
backport it:

1. Open the fix PR against `main`, as in "Fixing a Bug".
2. After it merges, branch from `release/v2` and run `git cherry-pick -x <sha>`. The `-x` flag
   records the original commit in the message.
3. Adapt the change to v2. Module names, file paths, and APIs differ between the two lines, and
   the cherry-pick may not apply cleanly. Run `swift test` on the branch.
4. Open the backport PR against `release/v2` with a `fix:` title. Link the `main` PR in the body.

A fix that only `release/v2` needs, because the code no longer exists on `main`, is the one
exception. Open it directly against `release/v2` and say so in the PR body.
Release-please publishes the patch release from `release/v2` (see [RELEASE.md](RELEASE.md)).

### Updating Dependencies

Dependencies are managed in `Package.swift`. Use version ranges when possible to allow flexibility.

