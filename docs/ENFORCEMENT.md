---
summary: The enforcement ladder (prose → comment → test → type/lint/CI rule) and
  the decision tree for adding a new rule. Where the rule LIVES is module shape
  (see MODULES.md); this doc is about how the rule STAYS TRUE.
---

# Enforcement

Rules written as prose drift the moment they're written. Conventions in this repo are encoded as enforcement layers — preference order **types > assertions > flake checks > prose**. The catalog of which claim sits at which rung lives in `INVARIANTS.md`; this doc is the *how*.

## The ladder

```
prose  →  comment  →  test  →  type / lint / CI rule
(weakest, drifts silently)              (strongest, can't drift)
```

Each rung is a different mechanism for staying true. **The bias is to push every load-bearing claim toward the rightmost rung the toolchain can reach.** A claim that lives only in prose is one refactor from silent staleness; a claim bound to a flake check fails CI the moment code diverges.

Conceptual model: see `CONCEPTS.md` § enforcement ladder.

## Rungs in this repo

### 1. Type system

Use option `type =` constraints first. Free, immediate, error message points at the option itself.

```nix
port = mkOption { type = types.port; ... };       # 0..65535 enforced at eval
scheme = mkOption { type = types.enum [ "http" "https" ]; ... };
audience = mkOption { type = types.enum [ "operator" "family" "public" ]; ... };
```

If the rule fits a type, write the type. Don't restate it in the description.

### 2. Module assertions

Cross-attribute invariants checked at NixOS eval time. Eval fails atomically with the message you wrote.

```nix
assertions = [
  {
    assertion = lib.length ports == lib.length (lib.unique ports);
    message = "lanRoutes have duplicate backend ports.";
  }
];
```

Live examples in `modules/effects/lan-route.nix` (port uniqueness, name regex, redirectPath shape). Use when a rule depends on multiple options together — derived properties, uniqueness across attrs, conditional requirements.

### 3. Custom flake checks

Derivations under `checks.${system}.<n>` in `flake.nix`. Run via `nix flake check`. Arbitrary shell, runs grep / find / scripts over the source tree. Use for repo-wide rules that don't live inside the module system.

```nix
forbidden-patterns = pkgs.runCommandLocal "forbidden-patterns" {
  nativeBuildInputs = [ pkgs.gnugrep ];
} ''
  cd ${./.}
  if grep -rn 'pattern' modules/ ; then
    echo "✗ explanation of what's wrong"
    exit 1
  fi
  touch $out
'';
```

Live examples in `flake.nix` `forbidden-patterns` (no inline PBKDF2 hashes, no caddy/blocky bypass, no `100.x.y.z` IP literals outside `identityFor`). Use for "no X in path Y" style rules.

If a rule needs AST awareness, graduate to a tree-sitter-nix wrapper. Not currently present; introduce only when grep stops being enough.

### 4. CI gate

`.github/workflows/check.yml` runs `nix flake check` on every push and pull_request. Backstop for cases where pre-commit was skipped: commits from a Mac without nix on PATH (the most common case here), `git commit --no-verify`, agents that bypass the hook. The check itself is just `nix flake check --print-build-logs`; everything in layers 1–3 runs through it.

## Decision tree — when to add a rule

When you write the words **"we should always..."** or **"don't ever..."** in prose, ask:

| Shape of the rule | Rung |
|---|---|
| Single option's value range / set | **type** (`types.port`, `types.enum`, `types.strMatching`) |
| Consistency across options (uniqueness, paths-XOR-skip, derived requirement) | **module assertion** |
| Forbidden text pattern in source files | **flake check (grep)** |
| Forbidden semantic pattern (needs eval introspection) | **flake check** via `nix eval` over `config.…` |
| AST-shape rule | **flake check** wrapping `tree-sitter-nix` (not yet present) |
| None of the above | **judgment** — that's what review is for. Don't write it down; it'll rot |

## When NOT to add a rule

- The rule's **false positives outweigh real catches**.
- The **cost of the constraint exceeds the cost of fixing the violation**.
- Only one person in the project ever cares; let that person enforce it in review.

**A check earns its keep when it would have caught a real mistake, not a hypothetical one.** Add when violations occur or are imminent — not preemptively.

## Live `nori.<X>` enforcement

The effect-interface family in `modules/effects/` is enforced by all four rungs simultaneously:

| Rung | Example |
|---|---|
| Type | `port`, `audience`, `scheme`, name regex on `nori.lanRoutes.<n>` |
| Assertion | port uniqueness; paths-XOR-skip on `nori.backups`; appliance role can't use `paths`; DynamicUser `StateDirectory` symlink-trap check |
| Flake check | `every-service-has-fs-hardening`, `every-service-has-backup-intent`, `forbidden-patterns` |
| CI gate | All of the above run on every push via `.github/workflows/check.yml` |

## Promoting a `[prose: unchecked]` claim

INVARIANTS.md tags each load-bearing claim with its current rung. A `[prose: unchecked]` entry is a **promotion candidate** — the goal is to move it down the table.

| Source claim | Likely promotion target | Mechanism |
|---|---|---|
| `disko*.nix` references disks by `/dev/disk/by-id/*` | flake check | `rg '/dev/(nvme[0-9]\|sda[0-9]?)'` over disko files |
| `nori.lanRoutes` names function over brand | flake check | grep declarations against a brand denylist |
| Workhorse vs appliance placement match | module assertion | for each service module, cross-check role tag |
| Every `Restart=on-failure` unit's `ExecStart` resolves to a real binary in the closure | flake check | iterate `config.systemd.services.*.serviceConfig.ExecStart`, assert first token is a path in the build closure |

See INVARIANTS.md § "Promotion work-list" for the live list.

## Code style enforcement

`nix flake check` runs `statix` (anti-patterns) + `deadnix` (unused bindings) + `nixfmt` (format) automatically. Pre-commit hook in `.githooks/pre-commit` runs the same on staged `.nix` changes.

Bypass with `git commit --no-verify` for emergencies only — CI catches what pre-commit skipped.
