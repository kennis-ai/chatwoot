# Krayin CRM Version Information

**Last Updated:** January 6, 2025  
**Research Source:** Official GitHub, Packagist, and Krayin Documentation

---

## Current Versions (January 2025)

### Krayin CRM Core
- **Latest Stable:** v2.1.5
- **Release Date:** September 19, 2025
- **Branch:** 2.1
- **GitHub:** https://github.com/krayin/laravel-crm/tree/2.1
- **Changelog:** https://github.com/krayin/laravel-crm/blob/2.1/CHANGELOG.md

### REST API Package
- **Latest Version:** v2.1.1
- **Release Date:** September 1, 2025
- **Packagist:** https://packagist.org/packages/krayin/rest-api
- **GitHub:** https://github.com/krayin/rest-api
- **Compatibility:** Requires Krayin v2.0.0 or later

### Dependencies
- **Laravel:** 11.x
- **PHP:** 8.2+
- **L5-Swagger:** ^8.6 (for API documentation)
- **Laravel Sanctum:** For API authentication

---

## Version History

### Major Releases

**v2.1.0** (March 26, 2025)
- IMAP Account Settings for email synchronization
- Events & Campaigns for marketing
- Magic AI Lead Creation (PDF/image extraction using OpenAI, Gemini, Deepseek, Grok, Llama)
- Mobile-responsive design
- Bulk Upload support (CSV, XLS, XLSX)
- Brazilian Portuguese language support

**v2.0.0** (August 30, 2024)
- Major version upgrade from 1.x series
- Laravel 11.x compatibility
- Improved architecture and performance
- Enhanced security features

**v1.x Series** (Prior to August 2024)
- Initial stable releases
- Foundation features

### Recent Patches (2.1.x Series)

**v2.1.5** (September 19, 2025) - Latest
- Bug fixes and stability improvements
- UI/UX enhancements
- Performance optimizations

**v2.1.4** (September 2025)
- Additional bug fixes
- Dashboard improvements

**v2.1.3** (August 2025)
- Mail functionality fixes
- Character limit adjustments

**v2.1.2** (July 2025)
- Permission fixes
- UI improvements

**v2.1.1** (June 2025)
- Initial bug fixes post-2.1.0 release

**v2.1.0** (March 26, 2025)
- Major feature release (see above)

---

## REST API Package Versions

### v2.1.1 (September 1, 2025) - Latest
- Compatible with Krayin v2.1.x
- L5-Swagger integration
- Bug fixes and improvements

### v2.1.0 (March 2025)
- Initial 2.1 series release
- Feature parity with Krayin 2.1.0

### v2.0.0 (August 2024)
- Compatible with Krayin v2.0.0
- Laravel 11 support

### v1.0.0 (Prior to 2024)
- Initial REST API package release
- Compatible with Krayin v1.x

---

## Breaking Changes

### From 1.x to 2.0
- Laravel version upgrade (10.x → 11.x)
- PHP version requirement (8.1 → 8.2+)
- Database schema changes
- API endpoint updates

### From 2.0 to 2.1
- **No breaking changes** - backward compatible
- New features additive only
- API endpoints remain compatible

---

## Installation Requirements for Chatwoot Integration

### Minimum Versions
```json
{
  "krayin/laravel-crm": "^2.1.5",
  "krayin/rest-api": "^2.1.1",
  "php": "^8.2",
  "laravel/framework": "^11.0"
}
```

### Recommended Setup (January 2025)
```bash
# Krayin CRM v2.1.5
composer create-project krayin/laravel-crm:^2.1.5

# REST API Package
composer require krayin/rest-api:^2.1.1

# Run setup
php artisan krayin-rest-api:install
```

### Environment Configuration
```env
# Krayin Version
APP_VERSION=2.1.5

# API Configuration
SANCTUM_STATEFUL_DOMAINS="${APP_URL}"
L5_SWAGGER_UI_PERSIST_AUTHORIZATION=true

# Laravel 11
APP_ENV=production
APP_DEBUG=false
```

---

## New Features in v2.1 Relevant to Integration

### 1. IMAP Integration
**Impact:** Potentially conflicts with Chatwoot email sync
- **Recommendation:** Disable Krayin IMAP when using Chatwoot email integration
- **Alternative:** Use only Chatwoot for email management

### 2. Magic AI Lead Creation
**Impact:** May auto-create leads from documents
- **Recommendation:** Consider integration with this feature
- **Opportunity:** Enhance Chatwoot with AI lead extraction

### 3. Bulk Upload
**Impact:** Positive for data migration
- **Use Case:** Initial contact/lead migration from Chatwoot
- **Formats:** CSV, XLS, XLSX supported

### 4. Mobile Responsive Design
**Impact:** None for API integration
- **Benefit:** Better user experience for Krayin users accessing synced data

### 5. Events & Campaigns
**Impact:** New entities to potentially sync
- **Future Enhancement:** Sync Chatwoot conversations to Krayin campaigns
- **Version:** Consider in future phases

---

## API Endpoint Structure (v2.1.1)

### Base URL Pattern
```
https://your-krayin-instance.com/api/admin/{resource}
```

### Available Resources (v2.1.1)
- `/api/admin/contacts/persons` - Person management
- `/api/admin/contacts/organizations` - Organization management
- `/api/admin/leads` - Lead management
- `/api/admin/activities` - Activity tracking
- `/api/admin/products` - Product catalog
- `/api/admin/quotes` - Quote management
- `/api/admin/emails` - Email management (new in 2.1)
- `/api/admin/events` - Events management (new in 2.1)
- `/api/admin/campaigns` - Campaigns management (new in 2.1)

### Documentation Access
- **Swagger UI:** `https://your-krayin-instance.com/api/admin/documentation`
- **Interactive Testing:** Available via L5-Swagger interface

---

## Compatibility Matrix

| Krayin Version | REST API Version | Laravel | PHP | Compatible |
|----------------|------------------|---------|-----|------------|
| v2.1.5         | v2.1.1          | 11.x    | 8.2+ | ✅ Recommended |
| v2.1.0-2.1.4   | v2.1.0-2.1.1    | 11.x    | 8.2+ | ✅ Yes |
| v2.0.x         | v2.0.0          | 11.x    | 8.2+ | ✅ Yes |
| v1.x           | v1.0.0          | 10.x    | 8.1+ | ⚠️ Legacy |

---

## Testing Environments

### Official Demo
- **URL:** https://demo.krayincrm.com/
- **REST API Demo:** https://demo.krayincrm.com/krayin-rest-api/
- **Version:** Usually latest stable (2.1.5)
- **Credentials:** Available on demo site

### Local Development
```bash
# Clone Krayin
git clone -b 2.1 https://github.com/krayin/laravel-crm.git
cd laravel-crm

# Install dependencies
composer install
npm install

# Setup
cp .env.example .env
php artisan key:generate
php artisan migrate
php artisan db:seed

# Install REST API
composer require krayin/rest-api
php artisan krayin-rest-api:install

# Serve
php artisan serve
```

---

## Upgrade Path for Existing Installations

### From v2.0 to v2.1
```bash
# Backup database
php artisan backup:database

# Update composer.json
composer require krayin/laravel-crm:^2.1.5
composer require krayin/rest-api:^2.1.1

# Run migrations
php artisan migrate

# Clear cache
php artisan cache:clear
php artisan config:clear
php artisan view:clear
```

### From v1.x to v2.1
**Not recommended for direct upgrade**
- Requires intermediate upgrade to v2.0
- Significant breaking changes
- Recommend fresh installation and data migration

---

## Known Issues & Limitations

### REST API Package (v2.1.1)
- **Open Issues:** 143 on GitHub (as of January 2025)
- **Common Issues:**
  - Token expiration handling
  - Pagination limits
  - Rate limiting not enforced
  - Validation error messages

### Krayin v2.1.5
- **Stable Release:** Yes
- **Production Ready:** Yes
- **Known Bugs:** Minor UI/UX issues (see changelog)

---

## Support & Resources

### Official Resources
- **Documentation:** https://devdocs.krayincrm.com/
- **API Docs:** https://apidoc.krayincrm.com/api/documentation
- **GitHub:** https://github.com/krayin
- **Community:** https://forums.krayincrm.com/

### Developer Resources
- **Packagist:** https://packagist.org/packages/krayin/rest-api
- **Upgrade Guide:** https://devdocs.krayincrm.com/2.0/prologue/upgrade-guide.html
- **API Reference:** https://devdocs.krayincrm.com/1.x/api/

---

## Recommendations for Chatwoot Integration

### Target Versions
✅ **Use:** Krayin v2.1.5 + REST API v2.1.1  
✅ **Minimum:** Krayin v2.0.0 + REST API v2.0.0  
❌ **Avoid:** Krayin v1.x (legacy)

### Compatibility Notes
1. **New Features (v2.1):** Consider future integration opportunities
2. **IMAP Conflict:** Document potential email sync conflicts
3. **Bulk Upload:** Leverage for initial data migration
4. **Mobile Responsive:** No impact on API integration

### Testing Strategy
1. Test against official demo first
2. Set up local Krayin v2.1.5 instance
3. Verify REST API package v2.1.1 installation
4. Test all CRUD operations via Swagger UI
5. Document any version-specific behaviors

---

**Document Status:** ✅ Complete  
**Verified:** January 6, 2025  
**Next Review:** June 2025 (or upon major Krayin release)
