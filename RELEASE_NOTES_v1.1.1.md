# MST v1.1.1

MST v1.1.1 is a security-hardening patch release that supersedes v1.1.0. Upgrading is recommended for all users.

MRRF1 text sanitization and JSON escaping now strip ASCII control characters (`0x00`-`0x1F`) and DEL. This ensures report documents remain compliant with RFC 8259 and prevents terminal escape sequences from attacker-influenced data—such as HTTP response headers, redirect URLs, or WP-CLI output from compromised sites—from reaching administrator terminals, Telegram reports, or downstream report consumers.
