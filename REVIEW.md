# Code Review Instructions

Instructions for AI code reviewers (CodeRabbit, Copilot, Claude, and others) on supabase-swift
pull requests. Human reviewers can use them too.

This file tells you what to check and how to report it. It does not repeat the rules. The rules
live in these files, and they win over this one:

- [AGENTS.md](AGENTS.md) — the entry point for agents.
- [CODE_STYLE.md](CODE_STYLE.md) — Swift style, naming, models, errors, streams, tests, and docs.
- [ARCHITECTURE.md](ARCHITECTURE.md) — modules, the HTTP layer, concurrency, and configuration.
- [CONTRIBUTING.md](CONTRIBUTING.md) — commits, specs, and `sdk-compliance.yaml`.
- [SDK engineering principles](https://github.com/supabase/sdk/blob/main/docs/principles.md) —
  the rules for every Supabase SDK.

Read the matching section before you comment. Cite it in the comment, for example
"CODE_STYLE.md, 'The error model'" or a link to a principle heading.

## How to review

1. Read the PR title and description first. Find the intent of the change.
2. Find the behavior that changed. Check that a test proves it.
3. Check the change against the priorities below, in order.
4. Report only findings you can defend with a line of code and a concrete failure.

### What a good comment looks like

- It points to one line or one small range.
- It says what goes wrong, with an input or a state that causes it.
- It cites the rule or the principle that the code breaks.
- It suggests a fix when the fix is short and clear.
- It says how sure you are. Mark a guess as a question, not as a defect.

### What not to comment on

- Formatting, import order, and line length. `swift-format` and `swiftlint` own these, and CI
  runs both.
- Spelling in code and docs. `cspell` runs in CI. Add a word to `dictionary.txt` only when the
  word is correct.
- Style preferences that no project doc states.
- Generated files: `**/Generated.swift`, `Package.resolved`, `CHANGELOG.md` (release-please
  writes it), and snapshot files.
- Code the PR does not change. Mention a pre-existing bug only when the change makes it worse,
  and label it "pre-existing".
- Praise and summaries of the diff. The author knows what they changed.

## Priorities

Check in this order. Stop at the first level that has a blocking finding, but report all
findings you are sure of.

### 1. Correctness and safety

- Logic errors, wrong conditions, off-by-one errors, and unhandled cases.
- Data races. Stateful public clients are an `actor` or a `final class: Sendable`. Mutable state
  sits behind `LockIsolated` or an internal actor. Flag `NSLock`, `Mutex`, and Combine in new
  code. Flag `@unchecked Sendable` unless it wraps a Foundation bridge and has a comment that says
  why.
- Cancellation. An async API must return promptly when its task is cancelled, and it must throw
  `CancellationError`, never a wrapped error. Flag long-lived tasks that never end, and streams
  that do not end when the consumer task is cancelled.
- Trapping. Flag `try!`, `!`, `precondition`, and `fatalError` on any value that varies at
  runtime or comes from the server: a per-call parameter, a response header, a decoded payload, a
  close code. See CODE_STYLE.md "When trapping is allowed".
- Secrets in logs. Flag a log line that can carry a JWT, an API key, a password, a signed URL, or
  a full URL with a query string. HTTP traffic logs only at `.trace`.
- Retries. Flag a retry outside `RetryRequestInterceptor`, a retry of a non-idempotent request,
  and a retry of a request with a single-pass body. Check the module's policy in the ARCHITECTURE.md
  "Retries" table.
- Access tokens. In HTTP modules, middleware is the only way to put a token on a request. Flag a
  new `accessToken` setting on an HTTP module.

### 2. SDK principles

These are the most common design defects in an SDK. Check each one.

- [Clients are thin layers](https://github.com/supabase/sdk/blob/main/docs/principles.md#clients-are-thin-layers)
  and [Logic belongs in the service](https://github.com/supabase/sdk/blob/main/docs/principles.md#logic-belongs-in-the-service).
  Flag business logic that the service already does or should do.
- [Validation belongs to the service](https://github.com/supabase/sdk/blob/main/docs/principles.md#validation-belongs-to-the-service).
  Flag client-side checks that reject input the server accepts, such as length limits, formats,
  or allowed values.
- [The service owns its defaults](https://github.com/supabase/sdk/blob/main/docs/principles.md#the-service-owns-its-defaults).
  Flag a default value that the SDK sends but the server already sets. Prefer to omit the field.
- [Decoding is open to new values](https://github.com/supabase/sdk/blob/main/docs/principles.md#decoding-is-open-to-new-values).
  Flag a closed Swift `enum` for a value that the backend sends or receives. It must be a
  `RawRepresentable` struct with a non-failable `init(rawValue:)`. See CODE_STYLE.md "Enum-like
  Values". Flag decoders that fail on an unknown key or an unknown value.
- [Spec before code](https://github.com/supabase/sdk/blob/main/docs/principles.md#spec-before-code).
  When the PR changes behavior that a capability spec describes, the PR description must link the
  spec change in `supabase/sdk`, or say that no spec covers it.

### 3. Public API

A change to public API is hard to undo. Check it with care.

- Breaking changes. A removed, renamed, or changed public symbol needs a `feat!:` or `fix!:`
  title, and an entry in `V<N>_MIGRATION.md` and `docs/migrations/v<N>/<Module>.md`. Adding a
  case to a public `enum` is a breaking change.
- `sdk-compliance.yaml`. Any added, removed, renamed, or moved public symbol must update this
  file in the same PR. Flag a PR that changes public API but not this file.
- Naming. Check the Swift API Design Guidelines and CODE_STYLE.md "Naming": uniform acronyms
  (`userID`, `redirectURL`, never `userId`), one type per concept (`URL`, `UUID`, `Duration`,
  `Date`, never `TimeInterval`), boolean names that read as assertions, and the standard verbs
  and type suffixes.
- Method shape. Check CODE_STYLE.md "Method Parameters: Inline or Options". Settings go in an
  `<Action>Options` struct by the rules there. Each method family has its own options type.
- Configuration. Setup types end in `Configuration`. Per-call types end in `Options`. Never
  `Config`. Check the parameter order in CODE_STYLE.md "Client Configuration".
- Errors. Each module throws one `<Module>Error` with a `kind`. Check the wrapping rules in
  CODE_STYLE.md "The error model". Raw Foundation or Helpers errors must not escape. No public
  `isRetryable`.
- Models. Public model structs have `public var` properties and a public memberwise init.
  `Codable` direction matches use: `Decodable` for responses only, `Encodable` for requests only.
  Wire keys use explicit `CodingKeys`, never a key strategy.
- Observation. New observable sources return an `AsyncStream` from a method, never a callback
  or a stream property.
- Access control. `package` only for what another SDK module needs. `@_spi(Experimental)` is
  the only SPI name. A type that one module uses lives in that module, not in Helpers.
- Parity. The API should mirror supabase-js where the concepts match. Flag a gratuitous
  difference in names or behavior.

### 4. Tests

- New behavior and bug fixes need tests. A bug fix needs a test that fails without the fix.
- Tests use Swift Testing only: `@Suite`, `@Test`, `#expect`, `#require`. Flag `XCTest` and
  `XCTestCase`.
- Test function names have no `test` prefix. A suite name matches its file name.
- HTTP stubs use `ClosureTransport` or `RecordingTransport` from TestHelpers at the
  `ClientTransport` seam. Flag `URLProtocol` stubs outside the URLSession adapter tests.
- Flag tests that sleep for real time. Waits and retries use the injected `clock`.
- Flag tests that assert on implementation details instead of behavior.
- A change to the supported version of a Supabase service needs integration tests for the
  minimum supported version.

### 5. Documentation

- Every new public symbol has a `///` summary. Every public `throws` function has a `- Throws:`
  line that names the module error and the conditions.
- DocC symbol links must resolve. Every type a doc names must exist, and a public doc names only
  public types.
- When an open-set type changes shape, `Sources/Supabase/Supabase.docc/EnumsAndOpenSets.md`
  changes in the same PR.
- Update the README "Supabase Service Compatibility" section when a supported service version
  changes.
- Comments explain why, not what. Flag a comment that repeats the code.

## Area-specific checks

| Path | Check |
| --- | --- |
| `Sources/Auth/` | Session storage and refresh races. Tokens never logged. PKCE and OAuth flows match supabase-js. |
| `Sources/Realtime/` | Channel state transitions, reconnect and heartbeat timing, task cleanup on `disconnect()`. |
| `Sources/Storage/` | Upload bodies and resumable upload retries. Signed URLs never logged. |
| `Sources/PostgREST/` | Query string encoding and filter escaping. Builder chains stay value types. |
| `Sources/PostgrestMacros*/` | Macro diagnostics, and expansion tests for each new case. |
| `Sources/Helpers/` | Public surface holds only types two or more modules use. Changes affect every module. |
| `Sources/Supabase/` | The facade never drops or overwrites a value the user set. |
| `Package.swift`, `Package@swift-6.2.swift` | The two files stay in sync. A new dependency needs a reason in the PR. |
| `tools/supabase-typegen/` | Goldens and fixtures change together. See its README. |
| `.github/workflows/` | Pinned action versions, least-privilege `permissions`, no secrets in logs. |
| `sdk-compliance.yaml` | Each declared symbol exists. A member is declared with its owning type. |

## Severity

Label each finding with one severity:

- **Blocking** — a bug, a data race, a crash on runtime input, a leaked secret, an unmarked
  breaking change, or a missing `sdk-compliance.yaml` update.
- **Should fix** — a broken project rule, a missing test, or missing docs on public API.
- **Nit** — a small improvement. Keep nits few. Skip them on large PRs.

## Commits and PR titles

PR titles follow [Conventional Commits](https://www.conventionalcommits.org/): `feat`, `fix`,
`docs`, `test`, `refactor`, `perf`, `chore`, with an optional module scope such as
`fix(auth):`. release-please reads the title, so a wrong type gives a wrong version bump.
