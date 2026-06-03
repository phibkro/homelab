---
name: gotcha-macos-rsync-openrsync
description: USE WHEN writing rsync flags for a Mac → host transfer (`just remote`, manual rsync) — `/usr/bin/rsync` on Sequoia+ is openrsync (BSD), missing -A / -X / --info=stats2; worse, may exit 0 after dumping usage to stderr (set -e doesn't catch). Stick to `-aH --no-owner --no-group --stats --partial` OR `brew install rsync` for GNU.
---

# macOS rsync is openrsync, not GNU rsync

`/usr/bin/rsync` on Sequoia+ is `openrsync` (BSD reimplementation). Many GNU flags missing: `-A` (ACLs), `-X` (xattrs), `--info=stats2`. Worse: openrsync may exit 0 after dumping usage to stderr, so `set -e` doesn't catch it.

For Mac→host rsync, stick to BSD-supported subset: `-aH --no-owner --no-group --stats --partial`. Or install GNU rsync via `brew install rsync` (lands at `/opt/homebrew/bin/rsync`, ahead of `/usr/bin/rsync` on PATH).
