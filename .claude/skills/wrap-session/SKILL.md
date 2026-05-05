---
description: Run the homelab end-of-session wrap-up — push pending commits, refresh CLAUDE.md if reality shifted, archive resolved memory items, verify clean state, end with a tight summary that lets the next agent (likely you with zero context) land cleanly.
when_to_use: User signals the session is wrapping up — phrases like "wrap up", "ending session", "that's it for now", "we're done", "session end", "done for today", "let's wrap up", "anything else before we end?".
---

# Homelab session wrap-up

A new agent with zero context should be able to read `CLAUDE.md` + `git log --oneline -10` + the latest commits' bodies and know exactly where you left off. If they'd be confused, the wrap-up isn't done.

## Live context at invocation

- Working tree: !`git status --short`
- Pending unpushed commits: !`git log --oneline @{u}.. 2>/dev/null || echo "(branch not tracking remote)"`
- Recent commit history: !`git log --oneline -10`
- Active memory: !`ls /home/nori/.claude/projects/-home-nori-Downloads-homelab/memory/active/ 2>/dev/null`
- Failed units (station): !`systemctl --failed --no-pager 2>&1 | head`

## Procedure

### 1. Push pending commits

If any local-only commits exist, push them. Local-only commits are invisible to the next agent.

```bash
git push origin main
```

If a push fails, surface the reason and stop — don't try to force-push without explicit go-ahead.

### 2. Refresh CLAUDE.md if reality shifted

Walk the sections and update what changed this session. The drift-cost is asymmetric: a stale CLAUDE.md acts on the next agent immediately; an up-to-date one costs nothing.

- **Intro line** — host status changed (planned → live, etc.)
- **Current state** — topology, service placement, hardware changed
- **Outstanding** — prune items that are done; add new items the session surfaced
- **Procedures pointer** — if a new procedure used twice or more, codify it (preferably as a skill in `.claude/skills/<n>/` or a "How to" in CLAUDE.md if the trigger isn't clean)

If a *new pattern* landed twice or more during the session, that's the rule-of-three trigger to codify. The cross-host service split → "How to relocate a service to nori-pi" → `relocate-to-pi` skill is the precedent.

### 3. Update auto-memory (if cross-conversation facts shifted)

Memory lives in `/home/nori/.claude/projects/-home-nori-Downloads-homelab/memory/`. Don't duplicate what's already in CLAUDE.md — memory is for cross-project / user-personal facts.

- New active item the next session needs to pick up → write to `memory/active/<slug>.md` + index in `MEMORY.md`
- Resolved item from `memory/active/` → move to `memory/archive/` + drop the line from `MEMORY.md`
- New durable fact (user preference, project state, host topology) → write to the right subfolder (`feedback/`, `project/`, `user/`, `reference/`)

### 4. Verify clean state

Quick spot-check that nothing's mid-migration:

```bash
git status                        # should be clean (no in-flight changes)
just status                       # failed units empty, disks healthy, timers green
systemctl is-active <key services for the work this session touched>
```

If any host is unreachable (e.g. Pi after a tailscale SSH expiry), surface that explicitly so the user knows the next session may need to drive it from Mac.

### 5. End with a tight summary

One or two paragraphs covering:
- **What changed** — commits pushed, files modified, decisions made
- **What was learned** — a non-obvious finding worth carrying forward
- **What's the immediate next concrete thing** — for the next agent's first action

The summary is the bridge for the next agent. Specific is better than thorough — a fresh agent reading the prior turn should get oriented in under 30 seconds.

## What this skill does NOT do

- It does NOT push without checking the user's commit history first (force-push is destructive; surface and ask)
- It does NOT delete memory files without first archiving them (recovery via archive is cheap; deletion is permanent)
- It does NOT restart services, run drills, or make config changes — those would be in-flight work, not wrap-up

If the session ended mid-task, say so in the summary rather than masking the loose end. "Pi rebuild deferred — tailscale SSH browser-auth expired; next session can drive from Mac" is more useful than pretending it's done.
