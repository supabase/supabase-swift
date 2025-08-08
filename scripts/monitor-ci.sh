#!/bin/bash

# Monitor CI and release workflow status
# Usage: ./scripts/monitor-ci.sh

set -e

echo "🔍 Monitoring CI and release workflow status..."
echo ""

# Get the current branch
BRANCH=$(git branch --show-current)
echo "📍 Current branch: $BRANCH"

# Get the latest commit hash
COMMIT_HASH=$(git rev-parse HEAD)
echo "🔗 Latest commit: $COMMIT_HASH"

# Get the GitHub repository URL
REPO_URL=$(git config --get remote.origin.url)
if [[ $REPO_URL == *"github.com"* ]]; then
    REPO_NAME=$(echo $REPO_URL | sed 's/.*github\.com[:/]\([^/]*\/[^/]*\)\.git.*/\1/')
    echo "📦 Repository: $REPO_NAME"
else
    echo "❌ Not a GitHub repository"
    exit 1
fi

echo ""
echo "🌐 GitHub Actions URLs:"
echo "CI Workflow: https://github.com/$REPO_NAME/actions/workflows/ci.yml"
echo "Release Test Workflow: https://github.com/$REPO_NAME/actions/workflows/release-test.yml"
echo "Release Workflow: https://github.com/$REPO_NAME/actions/workflows/release.yml"
echo ""

echo "📋 Workflow Status:"
echo "1. CI workflow should trigger on push to $BRANCH"
echo "2. Release-test workflow should trigger when CI completes on $BRANCH"
echo "3. Check the URLs above for detailed logs"
echo ""

echo "🧪 Expected Test Results:"
echo "✅ CI workflow completes successfully"
echo "✅ Release-test workflow runs in dry-run mode"
echo "✅ No actual releases are created"
echo "✅ Semantic-release analyzes conventional commits"
echo "✅ Version update script is tested"
echo ""

echo "📝 Recent commits for semantic-release analysis:"
git log --oneline -5 --grep="feat\|fix\|perf\|docs\|style\|refactor\|test\|build\|ci\|chore" || echo "No conventional commits found in recent history"

echo ""
echo "🚀 To check workflow status:"
echo "1. Visit: https://github.com/$REPO_NAME/actions"
echo "2. Look for workflows triggered by the latest commits"
echo "3. Check the logs for any errors or warnings"
echo "4. Verify that no actual releases are created"
echo ""

echo "📊 To view specific workflow run:"
echo "Replace WORKFLOW_RUN_ID with the actual run ID from GitHub Actions"
echo "curl -H 'Authorization: token YOUR_TOKEN' \\"
echo "  https://api.github.com/repos/$REPO_NAME/actions/runs/WORKFLOW_RUN_ID"
