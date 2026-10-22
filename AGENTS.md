# Instructions for supabase-swift

The official Supabase SDK for Swift, mirroring the design of supabase-js. It provides a Swift
client for Auth, Database (PostgREST), Realtime, Storage, and Functions.

## Where to look

Read the matching file before you act:

- [ARCHITECTURE.md](ARCHITECTURE.md) — module layout, dependencies, the HTTP layer, and client
  configuration. Read it before you add a module, a dependency, or a cross-module type.
- [DEVELOPMENT.md](DEVELOPMENT.md) — requirements, build, test, format, lint, spell check, DocC,
  the local Supabase stack, integration tests, CI, and the support policy. Read it before you run
  any build, test, or lint command.
- [CODE_STYLE.md](CODE_STYLE.md) — Swift style, enum-like values, `Codable` direction, errors and
  when trapping is allowed, and test conventions. Read it before you write or review Swift code.
- [CONTRIBUTING.md](CONTRIBUTING.md) — commit conventions, `sdk-compliance.yaml`, and the
  feature, bug-fix, and dependency workflows. Read it before you commit or change public API.
- [tools/supabase-typegen/README.md](tools/supabase-typegen/README.md) — the typegen package, its
  goldens, and its fixtures. Read it before you touch the generator, the `@Table` macros, or an integration migration.
- [RELEASE.md](RELEASE.md) — release-please, release branches, and the typegen binary release.
  Read it before you touch versions, `CHANGELOG.md`, or release workflows.

## Notes for AI coding agents

- On macOS, run `swift test` and `swift build --build-tests` with the flags from
  "macOS test flags" in [DEVELOPMENT.md](DEVELOPMENT.md); without them, swift-snapshot-testing
  fails to compile
- Always run `./scripts/format.sh` before committing Swift code
- Run `swiftlint lint --strict` before committing; it must not report new violations
- Any change to public API (add, remove, rename, or move a symbol) updates
  `sdk-compliance.yaml` in the same commit — run `./scripts/check-compliance.sh`
  to check for stale entries before committing (see "Capability Compliance" in
  [CONTRIBUTING.md](CONTRIBUTING.md))
- Ensure new public APIs have DocC documentation comments
- Add tests for all new functionality
- Keep changes minimal and focused
- Respect the existing architecture and patterns
- Check that changes work on all supported platforms when possible
- Use snapshot testing for complex response structures
- Maintain Sendable conformance for Swift 6 compatibility
- When adding async code, ensure proper task cancellation handling
- Review the CI workflow to understand what checks will run
