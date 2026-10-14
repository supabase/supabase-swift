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
root `V<N>_MIGRATION.md` — see the writing-migration-guides skill for the format.

## Capability Compliance

`sdk-compliance.yaml` declares this SDK's public API against the
[supabase/sdk](https://github.com/supabase/sdk) capability matrix.
`.github/workflows/validate-capabilities.yml` calls supabase/sdk's reusable
compliance workflow on every PR, and it does check for both newly added
public API not listed in the manifest and registered symbols the code no
longer has. But that workflow is not a required status check on `main` —
only `CI Success` (this repo's own `ci.yml`) and the WIP/draft gate are —
so a failing compliance check does not, by itself, block a merge.

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

This runs the same stale-entry check locally, without network access or a
checkout of `supabase/sdk`. Run it yourself before pushing a public-API
change — `validate-capabilities.yml` will eventually catch it too, but
since it isn't a required check, nothing stops a merge if you don't.

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

### Updating Dependencies

Dependencies are managed in `Package.swift`. Use version ranges when possible to allow flexibility.

