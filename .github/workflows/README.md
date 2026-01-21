# GitHub Actions Workflows

## Update Documentation Workflow

The `update-docs.yml` workflow automatically updates documentation in the [supabase/supabase](https://github.com/supabase/supabase) repository when PRs are merged in this repository.

### How it works

1. **Trigger**: Runs automatically when a PR is merged to `main` that includes changes to source code
2. **Analysis**: Claude analyzes the merged PR to identify changes that require documentation updates
3. **Update**: Claude creates a new branch in supabase/supabase and updates relevant documentation files
4. **PR Creation**: Claude creates a PR in supabase/supabase with the documentation changes

### Required Secrets

This workflow requires the following secrets to be configured in the repository settings:

#### `ANTHROPIC_API_KEY`
- **Description**: API key for Claude Code
- **How to get**:
  1. Go to [Anthropic Console](https://console.anthropic.com/)
  2. Create an API key with appropriate permissions
  3. Add as repository secret

#### `SUPABASE_DOCS_PAT`
- **Description**: GitHub Personal Access Token with access to supabase/supabase repository
- **Required permissions**:
  - `repo` - Full control of private repositories
  - `workflow` - Update GitHub Action workflows
- **How to create**:
  1. Go to GitHub Settings → Developer settings → Personal access tokens → Tokens (classic)
  2. Click "Generate new token (classic)"
  3. Set expiration and select required scopes
  4. Generate and copy the token
  5. Add as repository secret in this repository

**Note**: For organization repositories, you may need to use a GitHub App token instead of a PAT. See [GitHub's documentation](https://docs.github.com/en/apps/creating-github-apps/authenticating-with-a-github-app/about-authentication-with-a-github-app) for more details.

### Manual Trigger

You can manually trigger the documentation update workflow for a specific PR:

1. Go to Actions → Update Documentation
2. Click "Run workflow"
3. Enter the PR number you want to analyze
4. Click "Run workflow"

### Documentation Update Criteria

The workflow considers these types of changes for documentation updates:

- **API changes**: New methods, endpoints, parameters
- **Feature additions**: New functionality that needs to be documented
- **Breaking changes**: Changes that affect existing usage (MUST be documented)
- **Behavioral changes**: Changes that affect how users interact with the SDK

### Documentation Structure

Documentation is updated in these locations in supabase/supabase:

- `apps/docs/spec/`: API specifications and reference documentation
- `apps/docs/content/guides/`: User guides and tutorials

### Workflow Behavior

- **Preserves existing content**: Never removes existing documentation
- **Follows patterns**: Maintains existing formatting and conventions
- **Creates PRs**: All changes go through PR review process
- **Graceful exit**: If no updates are needed, the workflow explains why and exits

### Troubleshooting

#### Workflow doesn't trigger
- Check that the merged PR modified files in `Sources/` or `Package.swift`
- Verify the commit message contains "Merge pull request"

#### PR number extraction fails
- The workflow looks for PR numbers in these formats:
  - `Merge pull request #123`
  - `(#123)`
- If extraction fails, use the manual trigger with the PR number

#### Claude fails to create PR
- Verify `SUPABASE_DOCS_PAT` has correct permissions
- Check the Claude action logs for specific errors
- Ensure the token hasn't expired

#### No documentation updates
- Not all changes require documentation updates
- Claude will explain why no updates are needed in the workflow logs
- Review the analysis in the action output

### Related Files

- Workflow definition: `.github/workflows/update-docs.yml`
- Command template: `~/.claude/commands/update-supabase-client-lib-docs.md`

### Disabling the Workflow

To temporarily disable automatic documentation updates:

1. Edit `.github/workflows/update-docs.yml`
2. Add `if: false` to the job
3. Commit and push the change

To permanently disable:

1. Delete `.github/workflows/update-docs.yml`
2. Commit and push the change
