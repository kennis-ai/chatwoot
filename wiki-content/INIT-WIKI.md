# Initialize GitHub Wiki - Step by Step

GitHub requires the first wiki page to be created through the web interface. After that, you can clone and push updates via git.

## Step 1: Create First Page (1 minute)

1. **Open your browser** and go to:
   ```
   https://github.com/kennis-ai/chatwoot/wiki
   ```

2. **Click** the green button: **"Create the first page"**

3. **Page Title**: Enter `Home`

4. **Content**: Copy and paste this minimal content:
   ```markdown
   # Chatwoot Kennis AI Fork

   Documentation is being uploaded...
   ```

5. **Click** "Save Page" button at the bottom

✅ **Done!** The wiki is now initialized.

## Step 2: Upload All Documentation (automated)

Now that the wiki exists, run the upload script:

```bash
cd /Users/possebon/workspaces/kennis/chatwoot/wiki-content
./upload-wiki.sh
```

The script will:
- Clone the wiki repository
- Copy all documentation files
- Commit and push to GitHub
- Replace the temporary Home page with the full content

## Step 3: Verify

1. Go to: https://github.com/kennis-ai/chatwoot/wiki
2. You should see:
   - ✅ Home page with full content
   - ✅ GLPI Integration page
   - ✅ GLPI Quick Start Guide page
   - ✅ Keycloak Authentication page
   - ✅ Keycloak Setup Guide page
   - ✅ Sidebar navigation (on the right)

## Alternative: Manual Upload (if script fails)

If the automated script doesn't work:

### Method A: Clone and Push Manually

```bash
# 1. Clone the wiki (after Step 1 above)
cd /Users/possebon/workspaces/kennis
git clone https://github.com/kennis-ai/chatwoot.wiki.git
cd chatwoot.wiki

# 2. Copy all documentation
cp ../chatwoot/wiki-content/*.md .

# 3. Remove the README and upload script (not needed in wiki)
rm -f README.md upload-wiki.sh INIT-WIKI.md

# 4. Commit everything
git add .
git commit -m "docs: add GLPI and Keycloak documentation"

# 5. Push to GitHub
git push origin master
```

### Method B: Create Pages via Web UI

For each file in `wiki-content/`:

1. Go to https://github.com/kennis-ai/chatwoot/wiki
2. Click **"New Page"** button
3. **Title**: Use filename without `.md`:
   - `GLPI-Integration.md` → Title: "GLPI Integration"
   - `Keycloak-Authentication.md` → Title: "Keycloak Authentication"
   - etc.
4. Copy content from the file
5. Click **"Save Page"**

**Pages to create**:
- Home (already exists, update it)
- GLPI Integration
- GLPI Quick Start Guide
- Keycloak Authentication
- Keycloak Setup Guide
- _Sidebar (special page for navigation)

## Troubleshooting

### "Repository not found" when cloning

**Cause**: Wiki not initialized yet

**Solution**: Complete Step 1 first (create first page via web UI)

### Upload script fails

**Cause**: Various - permissions, network, etc.

**Solution**: Use Method A or B above

### Sidebar not appearing

**Cause**: Page must be named exactly `_Sidebar`

**Solution**:
1. Create new page via web UI
2. Title: `_Sidebar` (exactly, with underscore)
3. Copy content from `_Sidebar.md`
4. Save

### Formatting looks wrong

**Cause**: Markdown syntax issue

**Solution**:
1. Check the file in `wiki-content/` directory
2. Re-copy the content
3. Ensure no extra spaces or characters

## Quick Start Commands

```bash
# After creating first page via web UI:

cd /Users/possebon/workspaces/kennis/chatwoot/wiki-content
./upload-wiki.sh

# Or manually:
cd /Users/possebon/workspaces/kennis
git clone https://github.com/kennis-ai/chatwoot.wiki.git
cd chatwoot.wiki
cp ../chatwoot/wiki-content/*.md .
rm -f README.md upload-wiki.sh INIT-WIKI.md
git add .
git commit -m "docs: add GLPI and Keycloak documentation"
git push origin master
```

---

**Need Help?**
- Ensure you have write access to the repository
- Check GitHub Wiki is enabled in repository settings
- Try using GitHub web UI if git commands fail
