---
name: diagnose
description: A disciplined method for resolving stubborn bugs, test failures, and performance regressions — build a fast automated pass/fail feedback loop first, reproduce, rank falsifiable hypotheses, instrument with tagged probes, fix at the correct seam with a regression test, then clean up and post-mortem. Use when facing any bug, failing test, flaky behavior, or perf regression, before proposing fixes — especially when you've already tried a fix or two and they didn't hold.
---

# Diagnose

Random fixes waste time and breed new bugs. The discipline is: **don't fix what you
can't reproduce on demand.** Build the feedback loop first; everything else follows.

**Core principle:** a bug you can trigger with one fast, deterministic command is
half solved. A bug you're guessing at from a description is not yet being debugged.
(Pure logic is caught by tests-as-law; bugs hide in the effectful shell — so the loop
matters most exactly where the effects are.)

## Phase 1 — Build a feedback loop

Construct a fast, deterministic, automated pass/fail signal for the bug. Prefer the
highest-fidelity option you can build cheaply:

1. Failing test (unit / integration / e2e)
2. Curl/HTTP script against a dev server
3. CLI invocation with fixture input + snapshot diff
4. Headless-browser script
5. Replay a captured trace from disk
6. Minimal throwaway harness with mocked deps
7. Property/fuzz loop (1000 random inputs)
8. Bisection harness between known-good and known-bad
9. Differential loop (old vs. new version)
10. Human-in-the-loop script — last resort

Then sharpen the loop: **speed** (skip unrelated setup), **signal** (assert on the
specific symptom), **determinism** (pin time, seed RNG, isolate the filesystem).
Non-deterministic bug? Aim for a debuggable rate (50%+) — loop it 100×, parallelize,
add stress.

**If you cannot build a loop, stop and say so.** Document what you tried; request
environment access, captured artifacts (logs, HAR, core dumps), or instrumentation
permission. Don't proceed on guesses.

## Phase 2 — Reproduce

Run the loop and watch it fail. Do not advance until:

- It produces the user's described failure (not an adjacent bug).
- It reproduces across runs (or at a high rate for flaky bugs).
- You've captured the exact symptom (message, output, timing).

## Phase 3 — Hypothesize

Generate **3–5 ranked, falsifiable** hypotheses before touching anything. Each needs
an explicit prediction: "if X is the cause, changing Y makes it disappear / Z makes it
worse." Present the ranked list to your human partner before testing — their domain
knowledge often reorders or kills candidates instantly. Running autonomously with no
partner? State the ranked list and proceed — the falsifiable predictions are your gate.

## Phase 4 — Instrument

Map each probe to a specific prediction; change **one variable at a time**.

- Tool order: debugger/REPL inspection → targeted logs at the distinguishing
  boundary. Avoid "log everything and grep."
- Tag every debug log with a unique prefix (e.g. `[DEBUG-a4f2]`) so cleanup is a
  single grep.
- Performance regressions: establish a baseline measurement first, then bisect; logs
  are unreliable for timing.
- Proportionality: if the failing loop already localizes the bug (small, pure code
  where inspection suffices), skip the probes — instrumenting for its own sake is
  theater. Name the skip and why.

## Phase 5 — Fix at the correct seam, with a regression test

Write the regression test **before** the fix, at the **correct seam** — one that
exercises the real bug pattern at the call site, not a shallow single-caller stub.

1. Convert the minimized repro into a failing test at that seam.
2. Confirm it fails.
3. Apply the fix.
4. Confirm it passes, and the original Phase-1 loop is clean.

If no correct seam exists, document that and flag it for architecture work.

**Circuit-breaker — 3+ fixes failed?** If you've tried three fixes and each reveals a
new problem in a different place, or each needs "massive refactoring," **stop.** That
is not a failed hypothesis — it's a wrong architecture. Don't attempt fix #4. Question
the pattern with your human partner first, and hand it to `improve-codebase-architecture`.

## Phase 6 — Cleanup + post-mortem

- [ ] Original repro no longer reproduces.
- [ ] Regression test passes (or its absence is documented).
- [ ] All `[DEBUG-…]` probes removed (single grep).
- [ ] Throwaway harnesses deleted or clearly marked.
- [ ] The correct hypothesis is stated in the commit / PR message.

Then ask: **what change would have prevented this class of bug?** Hand that finding to
`improve-codebase-architecture`.

## Red flags — stop and return to Phase 1

- "Quick fix now, investigate later."
- Proposing a fix before you can reproduce on demand.
- Changing several things at once "to see what works."
- A fourth fix attempt after three failed (→ question the architecture).
