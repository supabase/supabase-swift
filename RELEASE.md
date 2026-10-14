# Release-Please Setup

This project uses [release-please](https://github.com/googleapis/release-please) to automate version management and package publishing.

## How it works

1. **Commit messages** follow the [Conventional Commits](https://www.conventionalcommits.org/) specification
2. **Release-please** analyzes commits and determines the next version number
3. **GitHub Actions** automatically creates release PRs and publishes releases

## Commit Message Format

```
<type>[optional scope]: <description>

[optional body]

[optional footer(s)]
```

### Types

- `feat`: A new feature (triggers minor version bump)
- `fix`: A bug fix (triggers patch version bump)
- `docs`: Documentation only changes
- `style`: Changes that do not affect the meaning of the code
- `refactor`: A code change that neither fixes a bug nor adds a feature
- `perf`: A code change that improves performance
- `test`: Adding missing tests or correcting existing tests
- `chore`: Changes to the build process or auxiliary tools

### Breaking Changes

Add `BREAKING CHANGE:` in the footer or use `!` after the type to trigger a major version bump:

```
feat!: remove deprecated API
```

or

```
feat: add new feature

BREAKING CHANGE: This removes the old API
```

## Release Process

### Automated Release Flow

1. **Push commits** to `main` branch with conventional commit messages
2. **Release-please** analyzes commits and creates a release PR when needed
3. **Review and merge** the release PR to trigger the actual release:
   - Version is updated in `Sources/Helpers/Version.swift`
   - `CHANGELOG.md` is updated
   - Git tag is created (e.g., `v2.33.0`)
   - GitHub release is published

### Release Branches

Release-please also supports `release/*` branches for managing releases from feature branches if needed.

`release/v2` ships v2 patch releases while `main` moves toward v3. Release-please finds the
last release of a branch from that branch's Git history: the newest release PR or release tag it
can reach. It reads `.release-please-manifest.json` only when the history has no release. Tags
from `release/v2` are not in the history of `main`, so a `release/v2` release does not change
what release-please on `main` treats as the last release. Copying the manifest version from
`release/v2` to `main` does not change it either.

To set the next version of `main`, set `release-as` in `release-please-config.json`. It is set to
`3.0.0-beta.1` for the first v3 beta. Remove it after that release ships; later betas then
continue from the `v3.0.0-beta.1` tag on `main`.

## Manual Release

To manually trigger the release-please workflow:

1. Go to Actions tab in GitHub
2. Select "Release" workflow
3. Click "Run workflow"

## Configuration Files

- `release-please-config.json`: Release-please configuration
- `.release-please-manifest.json`: Current version tracking
- `.github/workflows/release.yml`: GitHub Actions workflow

## Releasing the typegen binary

`supabase gen types --lang swift` runs `supabase-typegen`, so each release carries prebuilt
binaries: `supabase-typegen-macos-universal.tar.gz` (arm64 and x86_64) and
`supabase-typegen-linux-x86_64.tar.gz` (Swift runtime linked statically). Each archive holds only
the `supabase-typegen` executable. `.github/workflows/typegen-binaries.yml` builds them, and
`release.yml` calls it with the tag each time release-please creates a release. A pull request
that touches `tools/supabase-typegen` or that workflow runs the same build without a tag: it checks
the binaries and keeps them as workflow artifacts, and changes no release. To attach the binaries
to an existing release again, run the workflow by hand with its tag (only a tag that contains
`tools/supabase-typegen` builds).

`supabase-typegen --version` prints the release. The value lives in
`tools/supabase-typegen/Sources/SupabaseTypegen/Version.swift`, which release-please bumps with
`Sources/Helpers/Version.swift`. The workflow fails if the binary's version does not match the tag.
The generated file has no version in it, so the goldens do not change on each release.

The CLI (supabase/sdk#264) reads the supabase-swift version from the project's `Package.resolved`
and downloads `https://github.com/supabase/supabase-swift/releases/download/v<version>/<asset>`
itself. It takes the macOS archive on darwin arm64 and x64, and the Linux one on linux x64. It
extracts the entry named `supabase-typegen`. So the asset names, the `v<version>` tag, and one
`supabase-typegen` file at the archive root are a contract with the CLI. Change none of them
without a matching change in supabase/sdk.

When the download is not possible, the CLI falls back to `supabase-typegen` on the `PATH`. Users
install it like this (the README has the same steps):

```bash
VERSION=2.55.1 # the supabase-swift version the project uses
ASSET=supabase-typegen-macos-universal.tar.gz # or supabase-typegen-linux-x86_64.tar.gz
mkdir -p ~/.local/bin
curl -fsSL "https://github.com/supabase/supabase-swift/releases/download/v$VERSION/$ASSET" | tar -xz -C ~/.local/bin
supabase-typegen --version
```

