# Security

Report security issues privately to the maintainers through [GitHub private vulnerability reporting](https://github.com/InappifyLabs/flutter-sdk/security/advisories/new), when enabled. Avoid posting app keys, session tokens, Identity Tickets, receipt tokens, signatures or customer data in public issues.

The SDK's public bootstrap key belongs in client configuration. Backend/private keys and Web Identity Ticket issuance belong on the application's server. V2 mobile commerce requests use the backend-owned session token; compatibility setters on the Flutter facade do not replace that token.

See [security, diagnostics and cache behavior](doc/SECURITY_AND_CACHE.md) for platform boundaries and the limits of mirrored state. SDK builds and contract tests do not establish server deployment, store ownership or live payment behavior.
