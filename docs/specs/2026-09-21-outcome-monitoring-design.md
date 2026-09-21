---
date: 2026-09-21
status: frozen
---

# Outcome-based monitoring refinement

## Goal

Operator alerts describe failed user-visible or recovery outcomes rather than
only failed processes. Each requested outcome has one authoritative monitoring
mechanism and no duplicate notification path.

## User journey

1. Open the generated Pi monitoring projection and see explicit probes for DNS,
   authentication, canonical external HTTPS, application health, and TLS
   certificate lifetime.
2. Receive one operator alert after the configured failure threshold and one
   resolved notification when an outcome recovers.
3. Inspect backup-freshness, recovery-evidence-age, and disk-headroom timers as
   explicit systemd outcomes.
4. Trace every alert back to a typed inventory, backup, recovery, or storage
   declaration.

## Constraints

- Keep direct backend application probes. They distinguish application failure
  from entry-plane or TLS failure.
- Add canonical HTTPS probes rather than replacing backend probes.
- DNS monitoring must execute a real query and validate its answer. A TCP-open
  check is not DNS outcome evidence.
- Authentication monitoring must validate public OIDC discovery without using
  a user credential or mutating a session.
- Certificate monitoring uses Gatus' native certificate-expiration condition.
- Pi backup freshness keeps the deployed hourly Restic freshness unit as its
  single alert source.
- NixOS backup freshness must fail when no snapshot exists and must have a
  scheduled alerting path.
- Recovery-evidence age must derive from the accepted evidence registry rather
  than scraping prose.
- Disk alerts must cover declared backup/media mounts and fail when notification
  delivery fails. Do not add a second VictoriaMetrics alert for the same disk
  condition.
- Do not add maintenance suppression until real planned-work alert noise has
  been observed.

## Acceptance gates

- A projected DNS probe queries a declared homelab hostname through Pi-hole and
  checks both `NOERROR` and the declared address.
- A projected authentication probe requests canonical HTTPS OIDC discovery and
  checks the expected issuer.
- Canonical HTTPS probes alert on HTTP failure and on certificates with less
  than seven days remaining.
- Existing backend probes remain present and uniquely named.
- NixOS backup checks reject a missing latest snapshot and run from a scheduled,
  alerting service.
- A generated recovery-evidence freshness check alerts when accepted evidence
  exceeds its declared maximum age.
- Disk monitoring includes every mounted backup destination and does not swallow
  delivery failure.
- Focused projection/runtime checks and the repository validation suite pass.
- A live operator inspection confirms the deployed checks after activation.
