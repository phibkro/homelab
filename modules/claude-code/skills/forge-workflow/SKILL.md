---
name: forge-workflow
description: >-
  Design a new piece of development infrastructure — a workflow, convention,
  documentation or context-management scheme, progressive-disclosure structure,
  or enforcement rule — and EVALUATE whether it actually works. Use when about to
  create/codify a development *system* (not feature code, not a one-off task).
  The meta-process: how we make process here, and how we prove it.
---

# Forge a development system (and prove it works)

A development system — a workflow, a doc layout, a context-management scheme, an
enforcement convention — is itself a **designed artifact**. Design it with the
rigor you'd give code, make it **structural** rather than hopeful, and
**validate it empirically**: a process you can't observe working is just a wish.

This skill is the convergent meta-process. Reach for it when the human says some
form of "we keep doing X by hand — codify it," "we need a doc system for Y," or
"create a workflow / convention for Z." **Not** for feature code (that's `tdd`)
or a one-off task (just do it).

## Part 1 — Design the system

1. **Earn it (rule of three).** Don't codify a one-off. Codify a pattern that has
   already recurred (≈2–3×) or is about to. A premature convention is overhead
   with no payoff; wait for the pattern to declare itself, then capture it.

2. **Decompose, then rung each sub-claim at the right _grain_** (enforcement
   ladder: `prose → comment → test → type / lint / CI`). A convention is rarely
   one atomic rule — split it into sub-claims and place EACH on its own rung. For
   each, ask *what would make violating it a compile error or CI failure?* — but
   reach for the **strongest rung that models the real invariant at the right
   grain**, not the strongest-_looking_ one. Earning and rung-choice are
   **coupled**: the same evidence that earns a convention can prove the obvious
   rung wrong. _Cautionary example:_ "every feature updates the changelog" looks
   like a per-commit CI hook — but if the changelog is a _batched digest_, that
   hook fights the real cadence and trains throwaway entries; the right grain is
   a milestone-seam check, not per-commit. For the part that is **irreducibly
   un-checkable** (semantic fidelity — "is this _good_/truthful?"), don't just
   stop at prose: **tag it and back it with review** — name it a judgment claim
   and route it to the independent-context review (the `[judgment]`/`[prose]`
   tier pattern). Enforce the checkable sub-claims; backstop the residue.

3. **Design for the reader, progressively.** The cost of a system is paid at
   *read* time, repeatedly — so optimize navigability, not completeness. Tiered
   entrypoints (a one-screen map → per-doc summaries → detail → drill-down),
   scannable headers (frontmatter `summary`/`tags`), *navigate-don't-load*. If
   the artifact is injected into every context (e.g. an agent's system prompt),
   ruthlessly minimize it and push detail to read-on-demand homes.

4. **Bind claims to evidence.** "Done" is a *check*, not a vibe — especially for
   agents, which assert completion confidently and sometimes wrongly. Status
   claims should point at real artifacts (a file that exists, a test that runs,
   a commit). Prefer a mechanical check over a promise.

5. **One home per topic; cross-link, don't duplicate.** Drift is structural — two
   authoritative copies of the same fact *will* diverge. Make one layer canonical
   and derive/point from the rest; never co-author two.

6. **Record the decision only if it earns it.** An ADR/decision-log entry is
   warranted only when the choice is *all three*: hard to reverse, surprising
   without context, and a real trade-off. Most resolutions are a doc line, not an
   ADR. Don't manufacture ceremony — but do capture the *why*, so a fresh reader
   doesn't re-litigate it.

A guiding test, applied throughout: **would the strongest version of this
constraint be a type, a lint, or a CI rule?** If yes, and you left it as prose,
you're not done.

## Part 2 — Evaluate whether it works (the part most people skip)

A workflow you *wrote* is a hypothesis. Validate it the way you'd validate code:
by running it against reality.

- **The cold-agent dogfood.** Spawn a **fresh agent** (zero prior context,
  isolated workspace) with only a *representative task* + the system you built.
  Have it follow the process and keep a **friction log** — every point that was
  unclear, missing, ambiguous, contradictory, or guessed. The friction log is the
  output that matters; "it was fine" is useless.

- **Measure.** Time-to-oriented (how fast to productive), friction count, *did it
  follow the steps unaided*, and *did it reach a sound result*. These are your
  observability metrics for the process.

- **Consistency (pass^k).** Run *k* fresh agents on the same task in independent
  contexts and compare — exactly like a pass^k end-to-end test. A genuinely
  *observable/followable* process yields **consistent** results across runs. High
  variance means the process is under-specified or leans on tacit knowledge that
  isn't written down.

- **Iterate, and check it compounds.** Each friction → a fix → the next cold
  agent inherits it. Across runs, friction should **strictly decrease** and
  orientation time fall. If it *doesn't* compound, your fixes aren't structural
  (you patched a symptom, not the gap).

- **When the system _is_ a deterministic checker, test it against known-bad
  inputs first** — run the proposed check over historical _violating_ cases
  (e.g. past commits that broke the rule) and known-good ones: it must **fire on
  the bad and stay silent on the good** (zero false positives). A check that
  can't fail on the known-bad past is hollow. Cheaper and more decisive than a
  full dogfood for a pure checker.
- **Scale the evaluation to the system's size** (proportionality, same bar as
  the ADR step). A one-line convention riding an existing CI edge needs the
  known-bad check + maybe one cold-agent run; a whole new workflow earns the full
  pass^k spawn. Don't pass^k a one-liner.
- **The deep dividend.** Making a system *executable* — handing it to an agent to
  *follow* — reviews the **system itself**, not just its prose. An executable
  process exposes gaps that prose review (even careful review by the author)
  misses, because a different context can't share the author's blind spots. So
  the dogfood doubles as an independent-context design review. (This skill was
  itself validated this way: three agents pass^k-applying it converged on a sound
  design _and_ surfaced the decompose-first + known-bad-check gaps now folded in.)

## Done when

The system is **earned** (a real recurring need), on the **strongest enforcement
rung** the toolchain allows, **reader-navigable** (progressive disclosure),
**evidence-bound** (claims are checkable), **single-homed** (no drift), its *why*
recorded where it earns an ADR — and, decisively, **empirically validated**: a
cold agent followed it to a sound result, friction was logged and fixed, and (for
anything load-bearing) results were consistent across *k* runs.

If you documented a process but never watched a fresh agent try to follow it,
you've written a hypothesis, not a workflow. Hand it to `tdd` only for the code
parts; the system itself is proven by the dogfood, not by assertion.
