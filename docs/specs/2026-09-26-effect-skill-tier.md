# Effect skill tier for /srv/share/projects

Status: frozen for implementation on 2026-09-26 (operator decisions in this session). Remove this specification when the checks below run and the enduring rules live in `docs/PROJECTS.md`, the skills, and the profiles.

## Goal

Every agent that writes TypeScript under `/srv/share/projects` writes native Effect: it looks up the version-exact Effect guidance and examples before writing, uses an Effect construct wherever one exists, and falls back to plain TypeScript or another package only after it has established that Effect cannot express or compose the intent. Guidance teaches it; lint rules, type checks, and tests enforce it.

## Evidence

- Measured 2026-09-26: OMP stops its upward context walk at the repository root for repositories outside `$HOME`. From inside `/srv/share/projects/vektorprogrammet/mono-web`, neither `/srv/share/projects/AGENTS.md` nor skills in `/srv/share/projects/.agents/skills` nor agents in `/srv/share/projects/.omp/agents` were discovered; from `/srv/share/projects` itself, all three were. Probe method: `omp -p` asked the session to name a probe skill and agent.
- Research (session reports `EffectOfficialPractices2`, `OpencodeEffectPractices2`, `EffectSkillEcosystem2`; the operator's ChatGPT research pack `effect-v4-skill-research-pack-2026-09-26.zip`):
  - Upstream Effect ships version-exact `AGENTS.md` + type-checked `ai-docs` in the installed package; its `effect-development` skill says to search those first and to be "ready when every material Effect API has matching local guidance, or the search established that none exists".
  - OpenCode, Hazel, and Cap document Effect conventions in `AGENTS.md` and skills but enforce almost nothing in CI. Every third-party pattern catalogue has drifted on API names.
  - Policy worth keeping: native construct → composition of native constructs → small domain abstraction built from Effect → boundary adapter → explicitly justified substitute with a retirement trigger. Pure deterministic transformations stay plain functions.

## Decisions

1. **Tier plumbing (operator decision: homelab OMP config points at the tier).** The homelab-managed OMP configuration sets `skills.customDirectories` to `/srv/share/projects/.agents/skills`, links the user agents directory to `/srv/share/projects/.omp/agents` (or declares that directory as an agents root by the supported mechanism), and the generated user `AGENTS.md` gains one instruction: sessions whose working directory is under `/srv/share/projects` read `/srv/share/projects/AGENTS.md` first. The tier directories are declarative links into versioned homelab sources, like `AGENTS.md -> homelab/docs/PROJECTS.md`.
2. **API authority is never copied.** Skills link to the installed `node_modules/effect/AGENTS.md`, `ai-docs/src`, and source, and to the official `effect-ts` skill. They never restate API signatures; they teach decisions, composition, verification, and the project's escape-hatch discipline.
3. **Skill primitives** (portable, Effect v4, in the tier): `effect-first` (router: establish versions, lookup order, the decision ladder, pure stays pure, done-means), `effect-domain-models`, `effect-services-layers`, `effect-errors-recovery`, `effect-resources-concurrency`, `effect-streams-protocols`, `effect-boundary-adapters`, `effect-persistence-workflows`, `effect-ui-lifetimes` (Foldkit), `effect-domain-constructs`, `effect-testing`, `effect-review-exceptions`. Seeded from the research pack's drafts, rewritten against the installed Effect 4.0.0-rc.116 guidance, with every rule linked to the enforcement that exists (an `effecttsgo/*` rule, a project rule, a test) or marked review-only.
4. **Profiles are materialized views** (in the tier's agents directory): `effect-engineering` (router + all core primitives), `effect-backend-engineering`, `effect-ui-development`, `effect-library-development`. Each is frontmatter `autoloadSkills` over primitives plus a short role prompt; each also lists `effect-house`, the convention name a repository uses for its own overlay skill (OMP ignores an unknown name, so repositories without an overlay still work).
5. **Repository overlays** carry house conventions only (constructs, composition roots, test platform, runtime bridges) and link to generated artifacts such as `docs/constructs.md`. They do not restate the primitives.
6. **Exceptions have a lifecycle.** A disable comment or a non-native substitute names a registered exception with scope, missing capability, native alternatives examined, verification, owner, and retirement trigger; retired when the native capability arrives.

## Checks (Done when)

1. From inside a repository under `/srv/share/projects` (e.g. `mono-web`), an `omp -p` probe session lists the tier skills and profiles and reports that it read `/srv/share/projects/AGENTS.md` (evidence recorded in the commit message).
2. A homelab eval check fails when a profile's `autoloadSkills` names a tier skill that does not exist (the repository overlay name `effect-house` is the one allowed external name), and when a skill's frontmatter violates the Agent Skills format (name equals directory, description with a use-when trigger).
3. Every skill links to the installed Effect guidance and contains no API signature restated from it; every rule in a skill names its enforcement or says review-only.
4. `docs/PROJECTS.md` states the Effect-first clause and the lookup order.
5. `nix flake check` and the workstation build pass; nothing is deployed without the operator's `just rebuild`.
