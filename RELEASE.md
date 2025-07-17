# Semantic Release Setup

This project uses [semantic-release](https://semantic-release.gitbook.io/) to automate version management and package publishing.

## How it works

1. **Commit messages** follow the [Conventional Commits](https://www.conventionalcommits.org/) specification
2. **Semantic-release** analyzes commits and determines the next version number
3. **GitHub Actions** automatically creates releases when changes are pushed to `main`

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

### Regular Releases (main branch)

1. Push commits to `main` branch
2. GitHub Actions runs semantic-release
3. If there are releasable changes:
   - Version is updated in `Sources/Helpers/Version.swift`
   - `CHANGELOG.md` is updated
   - Git tag is created
   - GitHub release is published

### Release Candidates (rc branch)

1. Push commits to `rc` branch
2. GitHub Actions runs semantic-release
3. If there are releasable changes:
   - Prerelease version is created (e.g., `2.31.0-rc.1`)
   - Version is updated in `Sources/Helpers/Version.swift`
   - `CHANGELOG.md` is updated
   - Git tag is created
   - GitHub prerelease is published

## Manual Release

To manually trigger a release:

1. Go to Actions tab in GitHub
2. Select "Semantic Release" workflow
3. Click "Run workflow"

## Configuration Files

- `.releaserc.json`: Semantic-release configuration
- `package.json`: Node.js dependencies
- `.github/workflows/release.yml`: GitHub Actions workflow
- `scripts/update-version.sh`: Version update script
