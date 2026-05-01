# Security Policy

## About This Project

Bantay Drive is an undergraduate thesis project developed at New Era University (2026).
It is an on-device Android application — no backend servers, no cloud sync, no user data
is transmitted externally.

## Current Version

| Version | Status |
|---------|--------|
| V3.1 (current) | Active — thesis submission version |
| V2.x and below | No longer maintained |

## Scope

Because this is an academic project with no live deployment or user accounts, the scope
of security concerns is limited. Issues we consider in scope:

- Vulnerabilities in how the app handles local SQLite data
- Improper file permissions on saved video clips or session logs
- Any unintended data exposure in the app's local storage

Out of scope (this app does not have):
- Authentication or login systems
- Network communication or APIs
- Cloud storage or remote databases
- Payment or personal data collection

## Reporting a Vulnerability

If you discover a security issue in this repository, **do not open a public GitHub issue.**

Contact the authors directly:

- **Juliana R. Mancera** — real.julianamancera@gmail.com
- **Pia Katleya V. Macalanda** — piav.macalanda@gmail.com

Please include in your report:
1. A description of the vulnerability
2. Steps to reproduce it
3. Potential impact

We will respond within **7 days** and will credit you in the repository if the issue is confirmed
and you consent to being named.

## Note on the Model

The trained DMS-HybridNet model (`dms_hybridnet_v3_float32.tflite`) is not included in
this public repository. If you have obtained a copy through other means, note that using
it outside of academic reference is prohibited under the repository license (CC BY-NC-ND 4.0).
