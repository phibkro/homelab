# Archived music-ingest compiler prototype

This directory preserves the accepted Julia/Catlab compiler prototype as
historical evidence. It is not an active source root, is not imported by the
homelab configuration, and is not part of the current verification workflow.
The direct implementation lives in `services/music-ingest/`.

The adjacent [acceptance report](../2026-09-06-music-ingest-acceptance.md)
records the scope and limits of its checks. `source.bundle` is a complete Git
bundle for the exact accepted candidate:

```text
commit:        bcc850e56633a82b3c3deb7fb22c20f5b24e18da
tree:          010a9ad4bff6215a870dd5b7d237ac3186bdf3b8
bundle sha256: c8ecee00f289ef32586e1ee503ad393fded1cc031920c0a9133bab960045127c
```

Inspect it without adding the prototype to the active repository:

```bash
git bundle verify docs/archive/reports/2026-09-06-music-ingest-compiler-prototype/source.bundle
git clone docs/archive/reports/2026-09-06-music-ingest-compiler-prototype/source.bundle /tmp/music-ingest-compiler-prototype
git -C /tmp/music-ingest-compiler-prototype checkout bcc850e56633a82b3c3deb7fb22c20f5b24e18da
```

The original raw gate logs remain auxiliary workstation evidence under
`.worktrees/two-host-migration-evidence/music-ingest/`. The committed bundle is
the durable source and history record; those local logs are not required to
reconstruct it.
