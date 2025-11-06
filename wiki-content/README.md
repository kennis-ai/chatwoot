# Chatwoot Kennis AI Fork - Wiki Content

This directory contains all the documentation pages for the GitHub Wiki. These pages document the custom features added to this fork (GLPI integration and Keycloak authentication).

## 📁 Files

| File | Purpose | GitHub Wiki Page |
|------|---------|------------------|
| `Home.md` | Main landing page | Home |
| `GLPI-Integration.md` | Complete GLPI integration guide | GLPI-Integration |
| `GLPI-Quick-Start-Guide.md` | Quick setup guide for GLPI | GLPI-Quick-Start-Guide |
| `Keycloak-Authentication.md` | Complete Keycloak auth guide | Keycloak-Authentication |
| `Keycloak-Setup-Guide.md` | Step-by-step Keycloak setup | Keycloak-Setup-Guide |
| `_Sidebar.md` | Wiki navigation sidebar | _Sidebar |

## 🚀 How to Upload to GitHub Wiki

GitHub Wiki pages can be managed through the web interface or by cloning the wiki repository.

### Method 1: Web Interface (Recommended for Initial Setup)

1. **Navigate to Wiki**
   ```
   https://github.com/kennis-ai/chatwoot/wiki
   ```

2. **Create Home Page** (if doesn't exist)
   - Click "Create the first page"
   - Copy content from `Home.md`
   - Click "Save Page"

3. **Create Each Additional Page**
   - Click "New Page" button
   - Page title: Use the filename without `.md` (e.g., "GLPI Integration")
   - Copy content from corresponding file
   - Click "Save Page"

4. **Create Sidebar**
   - While on any wiki page, click "Add custom sidebar"
   - Copy content from `_Sidebar.md`
   - Click "Save Page"

**Pages to Create**:
1. Home
2. GLPI Integration
3. GLPI Quick Start Guide
4. Keycloak Authentication
5. Keycloak Setup Guide
6. _Sidebar (for navigation)

### Method 2: Clone Wiki Repository

1. **Clone the Wiki**
   ```bash
   cd /Users/possebon/workspaces/kennis
   git clone https://github.com/kennis-ai/chatwoot.wiki.git
   cd chatwoot.wiki
   ```

2. **Copy All Files**
   ```bash
   cp ../chatwoot/wiki-content/*.md .
   ```

3. **Add, Commit, and Push**
   ```bash
   git add .
   git commit -m "docs: add GLPI and Keycloak documentation

   - Add comprehensive GLPI integration guide
   - Add GLPI quick start guide
   - Add Keycloak authentication guide
   - Add Keycloak setup guide
   - Add navigation sidebar
   - Add home page with overview"

   git push origin master
   ```

4. **Verify**
   - Visit: https://github.com/kennis-ai/chatwoot/wiki
   - Check all pages are visible
   - Verify sidebar navigation works

### Method 3: Automated Script

Save this as `upload-wiki.sh`:

```bash
#!/bin/bash
set -e

# Configuration
WIKI_DIR="/Users/possebon/workspaces/kennis/chatwoot.wiki"
CONTENT_DIR="/Users/possebon/workspaces/kennis/chatwoot/wiki-content"

# Clone wiki if it doesn't exist
if [ ! -d "$WIKI_DIR" ]; then
  echo "📥 Cloning wiki repository..."
  cd "$(dirname "$WIKI_DIR")"
  git clone https://github.com/kennis-ai/chatwoot.wiki.git
fi

# Copy files
echo "📝 Copying wiki content..."
cd "$WIKI_DIR"
cp "$CONTENT_DIR"/*.md .

# Commit and push
echo "🚀 Uploading to GitHub..."
git add .
git commit -m "docs: update documentation for GLPI and Keycloak features"
git push origin master

echo "✅ Wiki updated successfully!"
echo "📖 View at: https://github.com/kennis-ai/chatwoot/wiki"
```

Make executable and run:
```bash
chmod +x upload-wiki.sh
./upload-wiki.sh
```

## 📋 Page Structure

### Home
- Overview of Kennis AI fork
- Feature list
- Quick links to documentation
- Version history

### GLPI Integration
- Complete technical documentation
- Configuration options
- User guide
- Developer guide
- Troubleshooting

### GLPI Quick Start Guide
- 15-minute setup guide
- Step-by-step instructions
- Testing procedures
- Pro tips

### Keycloak Authentication
- Complete OIDC integration guide
- Configuration methods comparison
- Security information
- Architecture overview

### Keycloak Setup Guide
- 30-minute setup guide
- Keycloak configuration
- Chatwoot configuration
- Testing and troubleshooting

### Sidebar
- Navigation menu
- Organized by category
- Quick links

## 🔄 Updating Documentation

When making changes to documentation:

1. Edit files in `wiki-content/` directory
2. Commit changes to main repository
3. Re-upload to wiki using one of the methods above

## 📖 Link Format

Internal wiki links use double brackets:
```markdown
[[Page Title]]
```

Examples:
- `[[Home]]` → Home page
- `[[GLPI Integration]]` → GLPI Integration page
- `[[Keycloak Setup Guide]]` → Keycloak Setup Guide page

## ✅ Checklist

- [ ] Create Home page
- [ ] Create GLPI Integration page
- [ ] Create GLPI Quick Start Guide page
- [ ] Create Keycloak Authentication page
- [ ] Create Keycloak Setup Guide page
- [ ] Create sidebar navigation
- [ ] Verify all internal links work
- [ ] Check formatting displays correctly
- [ ] Test navigation menu

## 📞 Support

If pages don't appear:
1. Check GitHub Wiki is enabled for repository
2. Verify you have write access
3. Ensure markdown filenames don't have spaces
4. Try creating first page via web interface first

---

**Maintained by**: Kennis AI Team
**Version**: 1.0
**Last Updated**: 2025-11-05
