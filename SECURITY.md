# Security Policy

## Supported versions

The latest released version receives security fixes.

## Reporting a vulnerability

Please report security issues privately via GitHub Security Advisories
(the "Report a vulnerability" button on the repository's Security tab) rather
than opening a public issue.

Patina runs locally, performs no network telemetry, and never writes to the
SMC. Maintenance actions (cleanup, optimize) are confirmation-gated and logged
to `~/Library/Logs/ThermoMole/operations.jsonl`. Please include macOS version,
Mac model, and reproduction steps in your report.
