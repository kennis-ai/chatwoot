# Chatwoot Development Guidelines

## Build / Test / Lint

- **Setup**: `bundle install && pnpm install`
- **Run Dev**: `pnpm dev` or `overmind start -f ./Procfile.dev`
- **Lint JS/Vue**: `pnpm eslint` / `pnpm eslint:fix`
- **Lint Ruby**: `bundle exec rubocop -a`
- **Test JS**: `pnpm test` or `pnpm test:watch`
- **Test Ruby**: `bundle exec rspec spec/path/to/file_spec.rb`
- **Single Test**: `bundle exec rspec spec/path/to/file_spec.rb:LINE_NUMBER`
- **Run Project**: `overmind start -f Procfile.dev`

## Code Style

- **Ruby**: Follow RuboCop rules (150 character max line length)
- **Vue/JS**: Use ESLint (Airbnb base + Vue 3 recommended)
- **Vue Components**: Use PascalCase
- **Events**: Use camelCase
- **I18n**: No bare strings in templates; use i18n
- **Error Handling**: Use custom exceptions (`lib/custom_exceptions/`)
- **Models**: Validate presence/uniqueness, add proper indexes
- **Type Safety**: Use PropTypes in Vue, strong params in Rails
- **Naming**: Use clear, descriptive names with consistent casing
- **Vue API**: Always use Composition API with `<script setup>` at the top

## Styling

- **Tailwind Only**:  
  - Do not write custom CSS  
  - Do not use scoped CSS  
  - Do not use inline styles  
  - Always use Tailwind utility classes  
- **Colors**: Refer to `tailwind.config.js` for color definitions

## General Guidelines

- MVP focus: Least code change, happy-path only
- No unnecessary defensive programming
- Break down complex tasks into small, testable units
- Iterate after confirmation
- Avoid writing specs unless explicitly asked
- Remove dead/unreachable/unused code
- Don’t write multiple versions or backups for the same logic — pick the best approach and implement it
- Don't reference Claude in commit messages

## Project-Specific

- **Translations**:
  - **Primary Languages**: Always implement English (`en`) and Brazilian Portuguese (`pt_BR`) first
  - For new features, integrations, or UI components, include both `en` and `pt_BR` translations
  - Backend i18n: Update both `config/locales/en.yml` and `config/locales/pt_BR.yml`
  - Frontend i18n: Update both `app/javascript/dashboard/i18n/locale/en.json` and `app/javascript/dashboard/i18n/locale/pt_BR.json`
  - Other languages are handled by the community
  - **Integration-Specific Language Support**:
    - GLPI Integration: Must support English and Brazilian Portuguese
    - Keycloak Integration: Must support English and Brazilian Portuguese
    - Krayin CRM Integration: Must support English and Brazilian Portuguese
- **Frontend**:
  - Use `components-next/` for message bubbles (the rest is being deprecated)

## Ruby Best Practices

- Use compact `module/class` definitions; avoid nested styles

## Git Workflow

### Branch Naming Convention
- **Feature branches**: `feature/<feature-name>` (e.g., `feature/krayin-crm-integration`)
- **Fix branches**: `fix/<issue-description>` (e.g., `fix/api-token-validation`)
- **Hotfix branches**: `hotfix/<critical-fix>` (e.g., `hotfix/security-patch`)
- **Release branches**: `release/<version>` (e.g., `release/4.7.0`)

### Main Branches
- **main**: Production-ready code
- **develop**: Integration branch for features (if using gitflow)

### Development Workflow
1. Always create a feature/fix branch from `main` or `develop`
2. Implement changes in the feature branch
3. Update documentation in `.kennis` for technical implementation details
4. Update Wiki for user-facing documentation
5. Create pull request to merge back to base branch
6. After testing and review, merge to `main` for release

## Documentation Structure

- **Implementation plans**: Should be created at `.kennis` folder
- **User guides**: Should be created on Wiki as GitHub Wiki pages at `/Users/possebon/workspaces/kennis/chatwoot.wiki`
- **Development guides**: Should be created on Wiki as GitHub Wiki pages
- **Technical architecture**: `.kennis/` folder for implementation details
- **API documentation**: Wiki for usage examples and integration guides

## GitHub Issue Management

### Issue Tracking System
This project uses GitHub Issues for comprehensive task and bug tracking. All work should be organized into:

- **Milestones**: One for each phase of the implementation plan
- **Labels**: For categorization (enhancement, bug, documentation, testing, security, priority levels)
- **Issues**: Detailed tasks with acceptance criteria and checklists

### Working with Issues

#### Before Starting Work
1. Check open issues in the current milestone
2. Assign yourself to the issue you'll work on
3. Create a feature branch linked to the issue: `feature/<issue-number>-<description>`
   - Example: `feature/15-krayin-processor-service`

#### During Development
1. Reference the issue in commits: `git commit -m "feat: implement processor service (#15)"`
2. Update issue with progress comments
3. Check off completed tasks in the issue checklist
4. Link related issues if dependencies are discovered

#### When Completing Work
1. Ensure all tasks in the issue are completed
2. Update relevant documentation
3. Create PR with `Closes #<issue-number>` in description
4. Request review if needed

### Automatic Bug/Error Issue Creation

**IMPORTANT**: Whenever you encounter bugs, errors, or issues during development, automatically create a GitHub issue using the following workflow:

#### When to Create Issues Automatically
- **Build/Compilation Errors**: Any error during `bundle install`, `pnpm install`, etc.
- **Test Failures**: Failed RSpec tests, Jest tests, or integration tests
- **Runtime Errors**: Exceptions, errors, or unexpected behavior during execution
- **Security Vulnerabilities**: Any security concern discovered
- **Performance Issues**: Slow queries, memory leaks, or performance degradation
- **Integration Problems**: Issues with GLPI, Keycloak, Krayin CRM, or other integrations
- **API Errors**: Failed API calls, authentication issues, or data sync problems

#### Bug Issue Template
When creating bug issues, use this format:

```bash
gh issue create \
  --title "Bug: <concise description>" \
  --body "## Bug Description
<Clear description of the issue>

## Steps to Reproduce
1. Step one
2. Step two
3. Step three

## Expected Behavior
<What should happen>

## Actual Behavior
<What actually happens>

## Error Messages
\`\`\`
<paste error output>
\`\`\`

## Environment
- Ruby Version: <version>
- Rails Version: <version>
- Node Version: <version>
- Branch: <branch-name>

## Related Issues
- Related to #<issue-number> (if applicable)

## Severity
- [ ] Critical (blocks development)
- [ ] High (major functionality affected)
- [ ] Medium (feature impaired)
- [ ] Low (minor issue)

## Suggested Fix (if known)
<Your analysis or suggested solution>" \
  --label "bug,priority-high" \
  --assignee @me
```

#### Priority Labels for Bugs
- **priority-critical**: Critical bugs blocking progress, security issues
- **priority-high**: Major functionality affected but workarounds exist
- **priority-medium**: Bugs affecting functionality but with workarounds
- **priority-low**: Minor bugs, cosmetic issues

#### Examples

**Example 1: Test Failure**
```bash
gh issue create \
  --title "Bug: ContactMapper spec failing on phone number format" \
  --body "## Bug Description
The \`ContactMapper\` spec is failing when testing phone number formatting.

## Steps to Reproduce
1. Run \`bundle exec rspec spec/services/crm/krayin/mappers/contact_mapper_spec.rb\`
2. Test \`#format_phone_number\` fails

## Expected Behavior
Phone number should be formatted to E.164 standard

## Actual Behavior
TelephoneNumber gem throws parsing error

## Error Messages
\`\`\`
TelephoneNumber::InvalidNumber: Could not parse phone number
\`\`\`

## Severity
- [x] High (blocks testing)

## Suggested Fix
Add validation before parsing or improve error handling" \
  --label "bug,testing,priority-high,krayin-crm"
```

**Example 2: Runtime Error**
```bash
gh issue create \
  --title "Bug: ProcessorService raises error on missing person_id" \
  --body "## Bug Description
ProcessorService crashes when contact has no external person_id stored.

## Steps to Reproduce
1. Trigger conversation_created event
2. Contact has no contact_inbox with source_id
3. Error thrown in ProcessorService

## Expected Behavior
Should handle missing person_id gracefully

## Actual Behavior
NoMethodError: undefined method 'split' for nil

## Error Messages
\`\`\`
NoMethodError: undefined method 'split' for nil:NilClass
at app/services/crm/krayin/processor_service.rb:85
\`\`\`

## Severity
- [x] Critical (breaks conversation sync)

## Suggested Fix
Add nil check before calling extract_external_id" \
  --label "bug,security,priority-critical,krayin-crm"
```

### Issue Labels Reference

#### Integration Labels
- `glpi-integration`: GLPI CRM integration related
- `keycloak-integration`: Keycloak SSO/authentication related
- `krayin-crm`: Krayin CRM integration related

#### Type Labels
- `enhancement`: New features or improvements
- `bug`: Something isn't working
- `documentation`: Documentation improvements
- `testing`: Testing related
- `security`: Security related

#### Priority Labels
- `priority-critical`: Critical, must be addressed immediately
- `priority-high`: Important, should be addressed soon
- `priority-medium`: Should be addressed in current milestone
- `priority-low`: Nice to have, can be deferred

#### Phase Labels (for phased implementations)
- `phase-1`, `phase-2`, etc.: Link issues to specific implementation phases

#### Other Labels
- `good-first-issue`: Good for newcomers
- `help-wanted`: Extra attention needed
- `i18n`: Translation/internationalization related

### Viewing Project Status

#### Check Current Milestone Progress
```bash
gh issue list --milestone "Phase 2: Core Services & Mappers"
```

#### View All Open Issues
```bash
gh issue list --state open
```

#### View Issues by Label
```bash
gh issue list --label "bug,priority-high"
```

#### View Your Assigned Issues
```bash
gh issue list --assignee @me
```

#### View Integration-Specific Issues
```bash
gh issue list --label "krayin-crm"
```

### Best Practices
1. **One Issue = One Concern**: Keep issues focused on a single task or bug
2. **Descriptive Titles**: Use clear, searchable titles with integration prefix (e.g., "Krayin: ...", "GLPI: ...")
3. **Reference Issues**: Link related issues and PRs
4. **Update Progress**: Comment on issues with progress updates
5. **Close Issues**: Close issues when work is completed and merged
6. **Auto-Create on Errors**: Always create issues when encountering bugs
7. **Use Checklists**: Break down complex issues into actionable checkboxes
8. **Add Context**: Include code snippets, error logs, and environment details

## Enterprise Edition Notes

- Chatwoot has an Enterprise overlay under `enterprise/` that extends/overrides OSS code.
- When you add or modify core functionality, always check for corresponding files in `enterprise/` and keep behavior compatible.
- Follow the Enterprise development practices documented here:
  - https://chatwoot.help/hc/handbook/articles/developing-enterprise-edition-features-38

Practical checklist for any change impacting core logic or public APIs
- Search for related files in both trees before editing (e.g., `rg -n "FooService|ControllerName|ModelName" app enterprise`).
- If adding new endpoints, services, or models, consider whether Enterprise needs:
  - An override (e.g., `enterprise/app/...`), or
  - An extension point (e.g., `prepend_mod_with`, hooks, configuration) to avoid hard forks.
- Avoid hardcoding instance- or plan-specific behavior in OSS; prefer configuration, feature flags, or extension points consumed by Enterprise.
- Keep request/response contracts stable across OSS and Enterprise; update both sets of routes/controllers when introducing new APIs.
- When renaming/moving shared code, mirror the change in `enterprise/` to prevent drift.
- Tests: Add Enterprise-specific specs under `spec/enterprise`, mirroring OSS spec layout where applicable.

## Version Control and Tagging

- Follow semantic versioning pattern: `v4.7.0-kennis-ai.1.0.0`
- Base version follows upstream Chatwoot version (e.g., `v4.7.0`)
- Custom suffix follows semantic versioning for custom features (e.g., `-kennis-ai.1.0.0`)
- Tag format based on implementation type:
  - Feature: Increment MINOR version (e.g., `1.0.0` → `1.1.0`)
  - Fix: Increment PATCH version (e.g., `1.0.0` → `1.0.1`)
  - Breaking change: Increment MAJOR version (e.g., `1.0.0` → `2.0.0`)