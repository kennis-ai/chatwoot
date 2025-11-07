# Release Quick Start Guide

Quick reference for creating releases in Chatwoot Kennis AI edition.

## TL;DR - Create a Release

```bash
# 1. Create and push an annotated tag
git tag -a v4.7.0-kennis-ai.1.2.3 -m "Release v4.7.0-kennis-ai.1.2.3 - Brief Description

## What's Changed
- Feature or fix description here

## Upgrade Instructions
- Pull new image and restart"

git push origin v4.7.0-kennis-ai.1.2.3

# 2. Monitor build (automatic)
gh run watch --repo kennis-ai/chatwoot

# 3. Done! Release created automatically after Docker build completes
```

## Version Number Format

```
v4.7.0-kennis-ai.1.2.3
└─┬─┘           └──┬──┘
  │                 └─ Custom version (semantic)
  └─ Base Chatwoot version
```

**Increment:**
- **Patch** (1.2.3 → 1.2.4): Bug fixes only
- **Minor** (1.2.3 → 1.3.0): New features, non-breaking
- **Major** (1.2.3 → 2.0.0): Breaking changes

## Common Commands

### Create Release (Automatic - Recommended)

```bash
# With detailed annotation
git tag -a v4.7.0-kennis-ai.1.2.3 -m "Release v4.7.0-kennis-ai.1.2.3 - Title

## What's Changed
- Change 1
- Change 2

## Upgrade Instructions
1. Pull image
2. Restart services"

git push origin v4.7.0-kennis-ai.1.2.3
```

### Create Release (Manual)

```bash
# If automatic release fails or needs recreation
gh workflow run create_release.yml \
  --repo kennis-ai/chatwoot \
  --field tag=v4.7.0-kennis-ai.1.2.3
```

### Monitor Release Process

```bash
# Watch all workflows
gh run watch --repo kennis-ai/chatwoot

# Check specific workflow
gh run list --workflow=create_release.yml --repo kennis-ai/chatwoot

# View logs
gh run view <run-id> --repo kennis-ai/chatwoot --log
```

### View Releases

```bash
# List all releases
gh release list --repo kennis-ai/chatwoot

# View specific release
gh release view v4.7.0-kennis-ai.1.2.3 --repo kennis-ai/chatwoot

# Download release assets
gh release download v4.7.0-kennis-ai.1.2.3 --repo kennis-ai/chatwoot
```

### Test Docker Image

```bash
# Pull image
docker pull ghcr.io/kennis-ai/chatwoot:v4.7.0-kennis-ai.1.2.3

# Test run
docker run --rm ghcr.io/kennis-ai/chatwoot:v4.7.0-kennis-ai.1.2.3 --version

# Multi-platform test
docker pull --platform linux/amd64 ghcr.io/kennis-ai/chatwoot:latest
docker pull --platform linux/arm64 ghcr.io/kennis-ai/chatwoot:latest
```

## Tag Annotation Template

### Minimal (Auto-generated changelog from commits)

```bash
git tag -a v4.7.0-kennis-ai.1.2.3 -m "Release v4.7.0-kennis-ai.1.2.3"
```

### Recommended (Detailed notes)

```bash
git tag -a v4.7.0-kennis-ai.1.2.3 -m "Release v4.7.0-kennis-ai.1.2.3 - Brief Title

## What's Changed

### Features
- New feature description
- Another feature

### Bug Fixes
- Fix description
- Another fix

### Technical Changes
- Technical change 1
- Technical change 2

## Upgrade Instructions

1. Pull new image
2. Run migrations (if needed)
3. Restart services

## Additional Notes

Any important information for users."
```

## Conventional Commits (for Auto-generated Notes)

If you don't provide detailed tag annotation, use conventional commits:

```bash
git commit -m "feat: add new feature"
git commit -m "fix: resolve bug"
git commit -m "refactor: improve code structure"
git commit -m "docs: update documentation"
git commit -m "chore: update dependencies"
```

## Troubleshooting

### Release Not Created

```bash
# Check if Docker build succeeded
gh run list --workflow=publish_github_docker.yml --repo kennis-ai/chatwoot

# Check release workflow
gh run list --workflow=create_release.yml --repo kennis-ai/chatwoot

# Manually trigger release
gh workflow run create_release.yml \
  --repo kennis-ai/chatwoot \
  --field tag=v4.7.0-kennis-ai.1.2.3
```

### Update Tag Annotation

```bash
# Update existing tag
git tag -a v4.7.0-kennis-ai.1.2.3 -f -m "New annotation"
git push origin v4.7.0-kennis-ai.1.2.3 -f

# Recreate release
gh release delete v4.7.0-kennis-ai.1.2.3 --repo kennis-ai/chatwoot --yes
gh workflow run create_release.yml \
  --repo kennis-ai/chatwoot \
  --field tag=v4.7.0-kennis-ai.1.2.3
```

### Docker Build Failed

```bash
# Check build logs
gh run view <run-id> --repo kennis-ai/chatwoot --log

# Test locally first
docker build -f docker/Dockerfile -t chatwoot:test .

# Re-trigger build
git push origin v4.7.0-kennis-ai.1.2.3 -f
```

## Release Checklist

- [ ] All changes committed and pushed to main
- [ ] Version number determined (patch/minor/major)
- [ ] Tag annotation prepared (or commits follow conventional format)
- [ ] Local Docker build tested (optional but recommended)
- [ ] Tag created and pushed
- [ ] Docker build monitored and succeeded
- [ ] Release created automatically
- [ ] Release notes reviewed
- [ ] Docker images tested
- [ ] Deployment triggered (if applicable)

## Examples

### Example 1: Quick Patch Release

```bash
git commit -m "fix: resolve webhook timeout"
git tag -a v4.7.0-kennis-ai.1.2.4 -m "Release v4.7.0-kennis-ai.1.2.4 - Webhook Fix

## Bug Fixes
- Fixed webhook timeout issue

## Upgrade
Pull new image and restart."

git push origin main v4.7.0-kennis-ai.1.2.4
gh run watch --repo kennis-ai/chatwoot
```

### Example 2: Feature Release with Details

```bash
git commit -m "feat: add batch processing"
git commit -m "feat: add message scheduling"
git tag -a v4.7.0-kennis-ai.1.3.0 -m "Release v4.7.0-kennis-ai.1.3.0 - Batch Processing

## Features
- **Batch Processing**: Process multiple messages at once
- **Message Scheduling**: Schedule messages for future delivery

## Upgrade
1. Pull: \`docker pull ghcr.io/kennis-ai/chatwoot:v4.7.0-kennis-ai.1.3.0\`
2. Migrate: \`bundle exec rails db:migrate\`
3. Restart services"

git push origin main v4.7.0-kennis-ai.1.3.0
gh run watch --repo kennis-ai/chatwoot
```

### Example 3: Emergency Hotfix

```bash
# Quick fix and release
git commit -m "fix: critical security patch"
git tag -a v4.7.0-kennis-ai.1.2.5 -m "Release v4.7.0-kennis-ai.1.2.5 - Security Patch

## Security
- Critical security patch applied

## Urgent Upgrade Required
Pull immediately: \`ghcr.io/kennis-ai/chatwoot:v4.7.0-kennis-ai.1.2.5\`"

git push origin main v4.7.0-kennis-ai.1.2.5
gh run watch --repo kennis-ai/chatwoot
```

## Docker Images

After release, images are available at:

```bash
# Specific version
ghcr.io/kennis-ai/chatwoot:v4.7.0-kennis-ai.1.2.3

# Latest
ghcr.io/kennis-ai/chatwoot:latest

# Platform-specific
docker pull --platform linux/amd64 ghcr.io/kennis-ai/chatwoot:latest
docker pull --platform linux/arm64 ghcr.io/kennis-ai/chatwoot:latest
```

## Additional Resources

- Full documentation: `.kennis/release-automation.md`
- Workflow file: `.github/workflows/create_release.yml`
- Docker workflow: `.github/workflows/publish_github_docker.yml`
