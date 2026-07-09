# supabase-swift

Supabase SDK for Swift. Modules: `Auth`, `PostgREST`, `Realtime`, `Storage`, `Functions`, `Supabase` (facade).

## Critical rules

- **Format before commit**: `./scripts/format.sh`
- **Tests**: `PLATFORM=IOS XCODEBUILD_ARGUMENT=test ./scripts/xcodebuild.sh` — not `swift test`
- **PRs only**: never push directly to `main`
- **Commits**: conventional commits — `feat:`, `fix:`, `refactor:`, `docs:`, `test:`, `chore:`

## Code

- `async/await` only — no completion handlers
- Strongly-typed errors; `IssueReporting` for issue reporting
- Public types: `Sendable` conformance required (Swift 6)
- New public APIs need DocC comments
