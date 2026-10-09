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

`release/v2` ships v2 patch releases while `main` moves toward v3. Release-please updates
`.release-please-manifest.json`, `CHANGELOG.md`, and `Sources/Helpers/Version.swift` only on
the branch it releases from. After each `release/v2` release, open a `chore` PR to `main` that
copies the new manifest version, the new `CHANGELOG.md` sections, and the new `_version` from
`release/v2`. Otherwise `main` keeps an old version, and a later patch release from `main`
proposes a version whose tag already exists.

## Manual Release

To manually trigger the release-please workflow:

1. Go to Actions tab in GitHub
2. Select "Release" workflow
3. Click "Run workflow"

## Configuration Files

- `release-please-config.json`: Release-please configuration
- `.release-please-manifest.json`: Current version tracking
- `.github/workflows/release.yml`: GitHub Actions workflow
