#!/bin/bash
# Upload documentation to GitHub Wiki
# Usage: ./upload-wiki.sh

set -e

# Configuration
WIKI_DIR="/Users/possebon/workspaces/kennis/chatwoot.wiki"
CONTENT_DIR="/Users/possebon/workspaces/kennis/chatwoot/wiki-content"

echo "📚 Chatwoot Wiki Uploader"
echo "========================="
echo ""

# Check if wiki repository exists
if [ ! -d "$WIKI_DIR" ]; then
  echo "📥 Wiki repository not found. Cloning..."
  cd "$(dirname "$WIKI_DIR")"

  if git clone git@github.com:kennis-ai/chatwoot.wiki.git 2>/dev/null; then
    echo "✅ Wiki cloned successfully"
  else
    echo "❌ Failed to clone wiki. It may not exist yet."
    echo ""
    echo "To initialize the wiki:"
    echo "1. Go to https://github.com/kennis-ai/chatwoot/wiki"
    echo "2. Click 'Create the first page'"
    echo "3. Add any content and save"
    echo "4. Run this script again"
    exit 1
  fi
  echo ""
fi

# Navigate to wiki directory
cd "$WIKI_DIR"

# Pull latest changes
echo "📥 Pulling latest changes..."
git pull origin master 2>/dev/null || git pull origin main 2>/dev/null || echo "⚠️  No remote changes"
echo ""

# Copy markdown files
echo "📝 Copying documentation files..."
cp "$CONTENT_DIR"/*.md . 2>/dev/null || {
  echo "❌ No markdown files found in $CONTENT_DIR"
  exit 1
}

# List files that will be uploaded
echo ""
echo "Files to upload:"
for file in *.md; do
  [ -f "$file" ] && echo "  - $file"
done
echo ""

# Check for changes
if [ -z "$(git status --porcelain)" ]; then
  echo "✅ No changes to upload (wiki is up to date)"
  exit 0
fi

# Show changes
echo "📊 Changes detected:"
git status --short
echo ""

# Confirm upload
read -p "Upload these changes to GitHub Wiki? (y/N): " -n 1 -r
echo ""

if [[ ! $REPLY =~ ^[Yy]$ ]]; then
  echo "❌ Upload cancelled"
  exit 0
fi

# Add all changes
git add .

# Commit
echo "💾 Committing changes..."
git commit -m "docs: update Kennis AI fork documentation

- GLPI integration guide
- GLPI quick start guide
- Keycloak authentication guide
- Keycloak setup guide
- Navigation sidebar
- Home page with feature overview

Version: v4.7.0-kennis-ai.1.0.0"

# Push
echo "🚀 Pushing to GitHub..."
git push origin master 2>/dev/null || git push origin main 2>/dev/null || {
  echo "❌ Failed to push to GitHub"
  echo "Branch might not be 'master' or 'main'"
  exit 1
}

echo ""
echo "✅ Wiki updated successfully!"
echo ""
echo "📖 View at: https://github.com/kennis-ai/chatwoot/wiki"
echo ""
