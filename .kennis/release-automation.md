# Release Automation

This document describes the automated release process for Chatwoot Kennis AI edition.

## Overview

The release process is fully automated through GitHub Actions. When you push a version tag, the following happens automatically:

1. Docker images are built for both `linux/amd64` and `linux/arm64` platforms
2. Images are pushed to GitHub Container Registry (GHCR)
3. A GitHub release is created with auto-generated release notes
4. Release notes include changelog, Docker image details, and version information

## Workflow Files

### 1. `publish_github_docker.yml`
Builds and publishes Docker images when a tag is pushed.

**Triggers:**
- Push of any tag (e.g., `v4.7.0-kennis-ai.1.2.2`)
- Manual workflow dispatch

**Actions:**
- Strips enterprise code
- Updates version in `config/app.yml`
- Builds multi-platform Docker images
- Pushes to GHCR with tag and `latest`

### 2. `create_release.yml`
Creates GitHub releases automatically after Docker images are built.

**Triggers:**
- Completion of `publish_github_docker.yml` workflow (automatic)
- Manual workflow dispatch (for retroactive releases)

**Actions:**
- Extracts version information from tag
- Generates changelog from commits
- Uses tag annotation if present
- Creates formatted release notes
- Creates GitHub release

## Creating a New Release

### Automatic Release (Recommended)

1. **Create and push a version tag with annotation:**

```bash
# For patch releases (bug fixes)
git tag -a v4.7.0-kennis-ai.1.2.3 -m "Release v4.7.0-kennis-ai.1.2.3 - Bug Fixes

## Bug Fixes

- fix: resolve authentication timeout issue
- fix: correct webhook payload format

## Docker Images

Available at ghcr.io/kennis-ai/chatwoot

Platforms: linux/amd64, linux/arm64"

git push origin v4.7.0-kennis-ai.1.2.3
```

2. **Monitor the workflows:**

```bash
# Watch Docker build
gh run watch --repo kennis-ai/chatwoot

# Or check specific run
gh run view <run-id> --repo kennis-ai/chatwoot
```

3. **Verify release creation:**

After the Docker build completes successfully, the release workflow will automatically trigger and create the GitHub release.

```bash
# List releases
gh release list --repo kennis-ai/chatwoot

# View specific release
gh release view v4.7.0-kennis-ai.1.2.3 --repo kennis-ai/chatwoot
```

### Manual Release Creation

If you need to create a release manually (e.g., for an existing tag):

```bash
# Via GitHub CLI
gh workflow run create_release.yml \
  --repo kennis-ai/chatwoot \
  --field tag=v4.7.0-kennis-ai.1.2.3
```

Or use the GitHub UI:
1. Go to Actions tab
2. Select "Create GitHub Release" workflow
3. Click "Run workflow"
4. Enter the tag name
5. Click "Run workflow"

## Tag Annotation Format

The workflow intelligently uses tag annotations to generate release notes. Here's the recommended format:

```
Release v4.7.0-kennis-ai.1.2.3 - Brief Description

## What's Changed

### Features
- Brief description of feature 1
- Brief description of feature 2

### Bug Fixes
- Brief description of fix 1
- Brief description of fix 2

### Technical Changes
- Detail about technical change 1
- Detail about technical change 2

## Upgrade Instructions

Steps for upgrading from previous version:
1. Step one
2. Step two

## Additional Notes

Any additional information relevant to this release.
```

**If no annotation is provided**, the workflow will automatically generate release notes from commit messages following conventional commits format (`feat:`, `fix:`, `refactor:`, etc.).

## Version Numbering

Follow semantic versioning with the Kennis AI suffix:

```
v<chatwoot-version>-kennis-ai.<major>.<minor>.<patch>

Example: v4.7.0-kennis-ai.1.2.3
         └─┬─┘           └──┬──┘
      Base version    Custom version
```

**When to increment:**
- **Patch** (`1.2.3` → `1.2.4`): Bug fixes, small improvements
- **Minor** (`1.2.3` → `1.3.0`): New features, non-breaking changes
- **Major** (`1.2.3` → `2.0.0`): Breaking changes, major refactors

## Release Notes Generation

The workflow automatically generates release notes with the following sections:

### From Tag Annotation (Priority)
If a multi-line tag annotation exists, it's used as the primary content.

### From Commits (Fallback)
If no annotation or single-line annotation:
- **Features**: Commits starting with `feat:`
- **Bug Fixes**: Commits starting with `fix:`
- **Refactoring**: Commits starting with `refactor:`
- **Documentation**: Commits starting with `docs:`
- **Maintenance**: Commits starting with `chore:`

### Always Included
- **Docker Images**: Links to GHCR images with supported platforms
- **Version Information**: Base Chatwoot version and integrations
- **Full Changelog**: Link to GitHub compare view

## Docker Images

Images are automatically published to:

```
ghcr.io/kennis-ai/chatwoot:v4.7.0-kennis-ai.1.2.3
ghcr.io/kennis-ai/chatwoot:latest
```

Supported platforms:
- `linux/amd64`
- `linux/arm64`

## Troubleshooting

### Release not created after Docker build

**Check workflow run:**
```bash
gh run list --workflow=create_release.yml --repo kennis-ai/chatwoot
gh run view <run-id> --repo kennis-ai/chatwoot --log
```

**Common issues:**
- Tag doesn't start with `v` (check workflow trigger condition)
- Docker build failed (check build logs)
- Permission issues (verify `GITHUB_TOKEN` has write access)

**Solution:**
Manually trigger the release workflow:
```bash
gh workflow run create_release.yml \
  --repo kennis-ai/chatwoot \
  --field tag=v4.7.0-kennis-ai.1.2.3
```

### Release notes are incomplete

**Issue:** Auto-generated notes missing information

**Solution:** Add detailed tag annotation when creating the tag:
```bash
# Edit tag annotation
git tag -a v4.7.0-kennis-ai.1.2.3 -f -m "Detailed release notes here..."
git push origin v4.7.0-kennis-ai.1.2.3 -f

# Then manually trigger release workflow
gh workflow run create_release.yml \
  --repo kennis-ai/chatwoot \
  --field tag=v4.7.0-kennis-ai.1.2.3
```

### Docker image build fails

**Check build logs:**
```bash
gh run list --workflow=publish_github_docker.yml --repo kennis-ai/chatwoot
gh run view <run-id> --repo kennis-ai/chatwoot --log
```

**Common issues:**
- Asset precompilation fails (check initializers)
- Platform-specific build issues (check runner logs)
- Registry authentication issues (verify `GITHUB_TOKEN`)

## Best Practices

1. **Always use annotated tags** for better release notes:
   ```bash
   git tag -a v4.7.0-kennis-ai.1.2.3 -m "Detailed message"
   ```

2. **Follow conventional commits** for automatic changelog generation:
   ```bash
   git commit -m "feat: add new feature"
   git commit -m "fix: resolve bug"
   ```

3. **Test locally** before tagging:
   ```bash
   # Build Docker image locally
   docker build -f docker/Dockerfile -t chatwoot:test .

   # Test the image
   docker run chatwoot:test
   ```

4. **Monitor builds** before release creation:
   ```bash
   gh run watch --repo kennis-ai/chatwoot
   ```

5. **Verify release** after creation:
   ```bash
   # Check release
   gh release view v4.7.0-kennis-ai.1.2.3 --repo kennis-ai/chatwoot

   # Test Docker image
   docker pull ghcr.io/kennis-ai/chatwoot:v4.7.0-kennis-ai.1.2.3
   ```

## Examples

### Example 1: Patch Release with Fixes

```bash
# Create commits
git commit -m "fix: resolve authentication timeout"
git commit -m "fix: correct webhook payload format"

# Create annotated tag
git tag -a v4.7.0-kennis-ai.1.2.3 -m "Release v4.7.0-kennis-ai.1.2.3 - Authentication Fixes

## Bug Fixes

- Fixed authentication timeout issue in Keycloak integration
- Corrected webhook payload format for Kanban events

## Upgrade Instructions

No special steps required. Pull the new image and restart."

# Push tag
git push origin v4.7.0-kennis-ai.1.2.3

# Monitor
gh run watch --repo kennis-ai/chatwoot
```

### Example 2: Minor Release with Features

```bash
# Create commits
git commit -m "feat: add batch message processing"
git commit -m "feat: implement message scheduling"
git commit -m "docs: update API documentation"

# Create annotated tag
git tag -a v4.7.0-kennis-ai.1.3.0 -m "Release v4.7.0-kennis-ai.1.3.0 - Message Processing

## Features

- **Batch Processing**: Process multiple messages in a single request
- **Message Scheduling**: Schedule messages for future delivery

## Documentation

- Updated API documentation with new endpoints
- Added examples for batch processing

## Upgrade Instructions

1. Pull new image: \`ghcr.io/kennis-ai/chatwoot:v4.7.0-kennis-ai.1.3.0\`
2. Run migrations: \`bundle exec rails db:migrate\`
3. Restart services"

# Push tag
git push origin v4.7.0-kennis-ai.1.3.0

# Monitor
gh run watch --repo kennis-ai/chatwoot
```

### Example 3: Manual Release Creation

```bash
# If automatic release failed or you need to recreate it

# Delete existing release (if needed)
gh release delete v4.7.0-kennis-ai.1.2.3 --repo kennis-ai/chatwoot --yes

# Trigger workflow manually
gh workflow run create_release.yml \
  --repo kennis-ai/chatwoot \
  --field tag=v4.7.0-kennis-ai.1.2.3

# Monitor workflow
gh run watch --repo kennis-ai/chatwoot

# Verify release
gh release view v4.7.0-kennis-ai.1.2.3 --repo kennis-ai/chatwoot
```

## Integration with CI/CD

The automated release process integrates with your deployment pipeline:

1. **Tag pushed** → Docker build triggered
2. **Docker build completes** → Release created
3. **Release created** → Deployment can be triggered

You can set up deployment automation to trigger when a new release is published:

```yaml
# .github/workflows/deploy.yml
on:
  release:
    types: [published]

jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - name: Deploy to production
        run: |
          # Your deployment script
          ./deploy.sh ${{ github.event.release.tag_name }}
```

## Security Considerations

1. **GITHUB_TOKEN**: Automatically provided by GitHub Actions with scoped permissions
2. **Container Registry**: Uses GitHub Container Registry (GHCR) with authentication
3. **Tag Protection**: Consider protecting version tags in repository settings
4. **Branch Protection**: Ensure main branch requires reviews before merging

## Future Enhancements

Potential improvements to the release automation:

- [ ] Automated testing before release creation
- [ ] Slack/Discord notifications for new releases
- [ ] Automatic deployment to staging environment
- [ ] Release notes translation (EN + PT-BR)
- [ ] Changelog aggregation across versions
- [ ] Integration with issue tracker for automatic linking
