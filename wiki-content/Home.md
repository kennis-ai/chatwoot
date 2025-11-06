# Chatwoot Kennis AI Fork - Documentation

Welcome to the Kennis AI fork documentation! This wiki covers the custom features and integrations added to Chatwoot for enhanced functionality.

## 🚀 Overview

This fork extends the official Chatwoot platform with enterprise-grade integrations and authentication mechanisms, specifically designed for IT service management and multi-tenant environments.

**Current Version**: `v4.7.0-kennis-ai.1.0.0`

## 📦 Custom Features

### 🔌 Integrations

#### GLPI Integration
Complete IT Service Management (ITSM) integration with GLPI, enabling seamless synchronization of contacts, conversations, and tickets between Chatwoot and GLPI.

- **Status**: ✅ Production Ready
- **Documentation**: [[GLPI Integration]]
- **Quick Start**: [[GLPI Quick Start Guide]]
- **Implementation**: [[GLPI Implementation Plan]]

**Key Features**:
- Contact synchronization (Chatwoot ↔ GLPI Users/Contacts)
- Automatic ticket creation in GLPI from conversations
- Message synchronization as ticket followups
- Bi-directional status updates
- Email/phone matching to prevent duplicates
- Session management with automatic reconnection

### 🔐 Authentication

#### Keycloak OpenID Connect
Enterprise SSO authentication using Keycloak as an OpenID Connect (OIDC) identity provider.

- **Status**: ✅ Production Ready
- **Documentation**: [[Keycloak Authentication]]
- **Configuration**: [[Keycloak Setup Guide]]

**Key Features**:
- Single Sign-On (SSO) with Keycloak
- Per-account configuration via UI or environment variables
- Encrypted client secret storage
- Multi-tenant support
- Connection testing before configuration
- Administrator-only access control

## 📚 Documentation Structure

### Integration Guides
- [[GLPI Integration]] - Complete GLPI integration documentation
  - [[GLPI Quick Start Guide]] - Get started quickly
  - [[GLPI Implementation Plan]] - Technical implementation details
  - [[GLPI Developer Guide]] - Developer reference
  - [[GLPI Troubleshooting]] - Common issues and solutions

### Authentication Guides
- [[Keycloak Authentication]] - Keycloak OIDC integration
  - [[Keycloak Setup Guide]] - Step-by-step setup
  - [[Keycloak UI Configuration]] - UI-based configuration

### Development
- [[Development Guidelines]] - Coding standards and practices
- [[Contributing]] - How to contribute to this fork
- [[Release Process]] - Version and release management

## 🔄 Version History

| Version | Date | Features |
|---------|------|----------|
| v4.7.0-kennis-ai.1.0.0 | 2025-11-05 | Keycloak OIDC authentication with UI configuration |
| v4.7.0-kennis-ai.0.9.0 | 2025-11-05 | GLPI integration (all 6 phases) |

## 🛠️ Quick Links

- [GitHub Repository](https://github.com/kennis-ai/chatwoot)
- [Upstream Chatwoot](https://github.com/chatwoot/chatwoot)
- [GLPI Project](https://glpi-project.org/)
- [Keycloak](https://www.keycloak.org/)

## 📞 Support

For issues specific to Kennis AI features:
- Create an issue on [GitHub](https://github.com/kennis-ai/chatwoot/issues)
- Use the `kennis-ai` label for fork-specific issues

For upstream Chatwoot issues:
- Check [Chatwoot Documentation](https://www.chatwoot.com/docs)
- Visit [Chatwoot Community](https://github.com/chatwoot/chatwoot/discussions)

## 🤝 Contributing

We welcome contributions! Please see our [[Contributing]] guide for details on:
- Code style and standards
- Branch naming conventions
- Commit message format
- Pull request process

---

**Maintained by**: Kennis AI Team
**Based on**: Chatwoot v4.7.0
**License**: MIT
