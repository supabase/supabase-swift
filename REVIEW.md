# Code Review Instructions

Instructions for AI code reviewers on supabase-swift pull requests. This file says how to review
and how to report. It does not state the rules. The rules live in these files:

- [AGENTS.md](AGENTS.md)
- [CODE_STYLE.md](CODE_STYLE.md)
- [ARCHITECTURE.md](ARCHITECTURE.md)
- [CONTRIBUTING.md](CONTRIBUTING.md)
- [SDK engineering principles](https://github.com/supabase/sdk/blob/main/docs/principles.md)

Do not copy rules from those files into this one. When a rule changes, change it there.

## How to review

1. Read the PR title and description. Find the intent of the change.
2. Find the behavior that changed. Check that a test proves it.
3. Check the change against the priorities below, in order.
4. Report only findings you can defend with a line of code and a concrete failure.

## Priorities

1. **Correctness and safety.** Bugs, data races, cancellation, crashes on runtime input, and
   secrets in logs. See ARCHITECTURE.md "Concurrency", "HTTP Layer", and "Logging", and
   CODE_STYLE.md "When trapping is allowed".
2. **SDK principles.** Check the change against each principle. Cite a principle by a link to
   its heading.
3. **Public API.** See CONTRIBUTING.md "Capability Compliance" and the API sections of
   CODE_STYLE.md. A public API change is hard to undo, so check it with care.
4. **Tests.** See CODE_STYLE.md "Testing Conventions".
5. **Documentation.** See CODE_STYLE.md "Documentation".

## How to write a comment

- Point to one line or one small range.
- Say what goes wrong, with an input or a state that causes it.
- Cite the rule: a file and a section name, or a principle link.
- Suggest a fix when the fix is short and clear.
- Write a guess as a question, not as a defect.

## What not to comment on

- Formatting, lint, and spelling. `swift-format`, `swiftlint`, and `cspell` run in CI.
- Style preferences that no project doc states.
- Generated files: `**/Generated.swift`, `Package.resolved`, `CHANGELOG.md`, and snapshots.
- Code the PR does not change. Mention a pre-existing bug only when the change makes it worse,
  and label it "pre-existing".
- Praise and summaries of the diff.

## Severity

Label each finding with one severity:

- **Blocking**: a bug, a data race, a crash on runtime input, a leaked secret, an unmarked
  breaking change, or a missing `sdk-compliance.yaml` update.
- **Should fix**: a broken project rule, a missing test, or missing docs on public API.
- **Nit**: a small improvement. Keep nits few. Skip them on large PRs.
