# Release Workflow Testing Guide

This document explains how to test the release workflow without actually creating releases.

## Overview

The release workflow has been improved with better error handling and direct push triggers. To test these changes safely, we've created multiple testing approaches.

## Testing Approaches

### 1. Local Testing (Recommended)

Run the local test script to verify all components work correctly:

```bash
./scripts/test-release.sh
```

This script will:
- ✅ Check Node.js and npm availability
- ✅ Install dependencies
- ✅ Run semantic-release dry-run
- ✅ Test the version update script
- ✅ Verify all required files exist
- ✅ Validate semantic-release configuration

### 2. GitHub Actions Testing

The `release-test.yml` workflow will run automatically when:
- Code is pushed to the `test-release-workflow` branch
- Manual workflow dispatch is triggered

This workflow:
- ✅ Uses the same setup as the real release workflow
- ✅ Runs semantic-release in dry-run mode
- ✅ Tests the version update script
- ✅ Validates configuration without creating releases

### 3. Manual Testing

To test specific components:

```bash
# Test semantic-release configuration
npx semantic-release --dry-run

# Test version update script
./scripts/update-version.sh 9.9.9-test
git checkout -- Sources/Helpers/Version.swift

# Test workflow files exist
ls -la .github/workflows/release.yml
ls -la .releaserc.json
ls -la package.json
```

## What Was Changed

### Release Workflow Improvements

1. **Direct push triggers**: Replaced `workflow_run` with direct `push` triggers for better reliability
2. **Removed problematic conditional**: The `if: "!contains(github.event.head_commit.message, 'skip ci')"` condition was removed because `workflow_run` events don't have direct access to commit messages
3. **Added better error handling**: 
   - Added `continue-on-error: false`
   - Added success check step
   - Added proper step IDs
4. **Improved structure**: Better formatting and organization

### New Testing Infrastructure

1. **`release-test.yml`**: GitHub Actions workflow for testing
2. **`test-release.sh`**: Local testing script
3. **`RELEASE_TESTING.md`**: This documentation

## Workflow Architecture

### Release Workflow (`release.yml`)
```
push (main/rc branches)
    ↓
release (semantic-release)
```

### Release Test Workflow (`release-test.yml`)
```
push (test-release-workflow branch)
    ↓
release-test (dry-run semantic-release)
```

## Testing Workflow

### Step 1: Local Testing
```bash
git checkout test-release-workflow
./scripts/test-release.sh
```

### Step 2: Push to GitHub
```bash
git push origin test-release-workflow
```

### Step 3: Create Test PR
1. Go to GitHub and create a PR from `test-release-workflow` to `main`
2. Add conventional commit messages to trigger semantic-release analysis
3. The `release-test.yml` workflow will run automatically

### Step 4: Verify Results
- Check the workflow logs in GitHub Actions
- Verify no actual releases are created
- Confirm all tests pass

## Conventional Commit Examples

To test semantic-release analysis, use these commit types:

```bash
# Minor version bump
git commit -m "feat: add new feature"

# Patch version bump  
git commit -m "fix: fix existing bug"

# No version bump
git commit -m "docs: update documentation"
git commit -m "test: add test coverage"
git commit -m "chore: update dependencies"
```

## Safety Features

- **Direct triggers**: Push triggers are more reliable than workflow_run
- **Dry-run mode**: All semantic-release operations run in dry-run mode
- **Test branch**: Workflow only runs on `test-release-workflow` branch
- **No actual releases**: No GitHub releases or tags are created
- **Reversible changes**: Version changes are reverted after testing

## Troubleshooting

### Common Issues

1. **Node.js not found**: Install Node.js 20 or later
2. **npm ci fails**: Delete `node_modules` and `package-lock.json`, then run `npm install`
3. **Permission denied**: Make sure `scripts/test-release.sh` is executable (`chmod +x scripts/test-release.sh`)

### Debug Commands

```bash
# Check Node.js version
node --version

# Check npm version  
npm --version

# Check semantic-release version
npx semantic-release --version

# Test specific semantic-release plugins
npx semantic-release --dry-run --debug
```

## Next Steps

Once testing is complete:

1. ✅ Verify all tests pass
2. ✅ Review workflow logs
3. ✅ Create PR to main branch
4. ✅ Merge changes
5. ✅ Monitor first real release

## Files Modified

- `.github/workflows/release.yml` - Improved release workflow with direct push triggers
- `.github/workflows/release-test.yml` - New test workflow with direct push triggers
- `scripts/test-release.sh` - Local testing script
- `RELEASE_TESTING.md` - This documentation
