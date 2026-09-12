---
summary: Generate desktop setting contracts from Nix and apply one real setting through a shared local service.
date: 2026-09-12
status: frozen; implementation authorized; workstation activation remains operator-gated
owner: operator
---

# Generated settings and local change service

## Goal

A user opens an independent Settings application and changes one real desktop setting.

The same setting appears in Vicinae from the same component declaration. Both clients show the same desired, resolved, and observed state.

Unknown values fail before any profile write or runtime change. An allowed value affects the real desktop and remains selected after service restart, login, and managed reapplication.

This milestone adds the shared change service required by the later nixpkgs Store milestone. It does not implement the Store.

## Implementation baseline

The Vicinae milestone is isolated in commit `27deced` on this branch.

Its saved-command checks, extension type check, focused Nix checks, and private launcher journey passed from the clean worktree.

The workstation is not activated. Continue implementation in this worktree and never evaluate the original mixed checkout from a client.

## User journey

1. Open **Desktop Settings** from the application menu or Vicinae.
2. Open **Desktop → Bar position**.
3. See the desired position, evaluated position, observed surface edge, and apply status.
4. Select `top` or `bottom`.
5. Preview the change.
6. Review the required managed generation and Waybar reload.
7. Apply the change.
8. Observe the real Waybar surface move to the selected edge.
9. Search **Bar position** in Vicinae and see the same resolved value.
10. Restart the service and start a new desktop session. The selected position remains authoritative.

If another client changes the profile before step 7, the apply fails as stale. The client reloads the newer revision before retrying.

## Pilot component

This milestone adds one new component setting declaration:

- Component ID: `desktop.waybar`.
- Setting ID: `position`.
- Title: **Bar position**.
- Type: enum.
- Writable values: `top` and `bottom`.
- Scope: user session.
- Live adapter: the `nori` session runtime agent reloads and observes `waybar.service`.
- Durable realization: integrated Home Manager configuration inside the NixOS generation.

The component maps `position` to `programs.waybar.settings.mainBar.position`.

The pinned Home Manager module supports `top`, `bottom`, `left`, and `right`. This component exposes only the safe horizontal positions.

`left` and `right` remain unavailable because the authored modules and styling assume a horizontal bar. The interface gives that reason.

The component output also exposes these policy-owned values as read-only:

- Waybar remains enabled.
- The patched package remains selected.
- Layer, module topology, margins, and CSS remain authored policy.
- The service remains attached to `hyprland-session.target`.

The Settings application disables these controls and gives this reason: **Managed by authored Nix policy**.

This setting is generation-backed. The `nori` session runtime agent reloads Waybar only after activation provides the matching generated configuration.

Clients show desired, resolved, active, and observed differences. They never rewrite desired intent from observed surface state.

## Why this pilot

The existing desktop already has all required real boundaries:

- `users/nori/programs/desktop/waybar.nix` owns the bar configuration, package, modules, style, and session lifecycle.
- The pinned Home Manager Waybar module declares position as an enum.
- The generated Waybar user unit has a supported reload action.
- `users/nori/programs/desktop/default.nix` owns `hyprland-session.target`.

The setting is reversible and visible at all times. The acceptance journey can observe the actual layer surface edge after reload.

Do not expose left or right until the component declares compatible vertical modules and styling.

Do not use Persona mode, Hyprlock policy, or Hyprland layout geometry as the first setting. Those choices add unrelated state or layout invariants.

## Component declaration

A component has one stable namespaced identity. Duplicate component and setting IDs fail evaluation.

The declaration owns:

- Setting types and defaults.
- Presentation metadata: title, group, description, control hint, and scope.
- Ownership metadata: writable or authored policy, with a reason.
- Apply class: live-only, live plus generation, or generation-only.
- Runtime-agent contract, when required.
- Generated launcher action metadata.
- NixOS or Home Manager realization.

The pilot declares `position` once through a small Nix helper around `lib.mkOption`. The helper records its presentation and ownership beside that option.

Do not add matching handwritten TypeScript unions. TypeScript clients consume generated JSON Schema and runtime data.

Most Nix options do not become writable desktop settings. Only explicit component declarations enter this interface.

## Generated contracts

Add Clan Core as a reviewed, pinned source before implementation. The repository does not currently pin Clan.

Use `clanLib.jsonschema.fromModule` or `fromOptions`. Do not use the historical `parseModule` blog API.

The reviewed upstream converter contract is:

- `fromOptions { typePrefix; input; output; readOnly; renamedTypes; } options`.
- `fromModule opts module`, with optional `opts.specialArgs`.
- JSON Schema draft 2020-12 output.
- Separate `$defs` named from `typePrefix` for input and output.
- No top-level `$ref`; consumers select the generated input or output definition explicitly.

Derive two option projections from one component declaration:

- Writable input options contain only explicit user-owned settings.
- Resolved output options contain writable values, policy fields, and derived fields.

Call the converter once for each projection. Emit only the input definition from the first call and only the output definition from the second.

The converter still traverses both modes during each call. Every projected type must therefore be supported.

Pass `readOnly.input = false` for the writable projection. Keep `readOnly.output = true` for the resolved projection.

The output schema describes the resolved data shape. A separate generated JSON projection contains actual evaluated values for one profile revision.

Unsupported Nix option types fail schema generation with their option location. Never weaken them to an unvalidated JSON value without an explicit component decision.

Nix evaluation remains the semantic authority. JSON Schema does not encode every assertion or cross-setting constraint.

Generated artifacts include:

- Writable settings input schema.
- Resolved settings output schema.
- Presentation catalog.
- Launcher setting actions.
- Nix realization input for one profile revision.

These files are derivations. A client never edits them.

## Dedicated profile authority

The rootless system service running as the dedicated
`nori-desktop-settings` UID owns the canonical, versioned authority state at
`/var/lib/nori-desktop-settings/`:

- `profile.json` is the canonical desired profile document.
- `jobs/` contains durable apply-job state and bounded logs.
- `previews/` contains durable preview state keyed to the exact profile
  revision and immutable build identity.

The dedicated UID owns this state root. It is not an XDG directory and it is
not owned by the `nori` user manager or by a client. The `nori` user reaches
the authority only through the authenticated public ingress described below.

The profile root object has a format version, monotonically increasing
revision, component values, and saved commands. This milestone moves saved
commands into this profile before the first workstation activation. The prior
launcher implementation is not yet deployed, so no active user data needs
migration. Remove the independent `saved-commands.json` authority during
implementation. Generated Vicinae scripts remain disposable projections.

The profile stores desired user intent only. It does not store:

- Evaluated policy as a second authority.
- Active generation identity.
- Observed service state.
- Job logs or results.
- Secrets.

Generated schemas and realizations belong in the Nix store.

Every profile replacement uses:

- A strict schema decode with unknown fields rejected.
- An expected revision.
- Exclusive serialized ownership.
- A new complete document.
- A durable atomic replacement: write, flush, rename, and flush the containing
  directory.

A stale expected revision returns a typed conflict. It never merges by last
writer wins.

## State model

Keep these states distinct:

| State | Meaning | Owner |
|---|---|---|
| Draft | Proposed values not yet committed | Change operation |
| Desired | Latest committed profile revision | `nori-desktop-settings` ProfileStore |
| Resolved | Nix-evaluated result for one desired revision | Evaluation adapter |
| Built | Store artifact produced for one resolved revision | Nix build adapter |
| Active | Running NixOS generation and its profile baseline | Activation observer |
| Observed | Current Waybar unit and layer-surface edge | `nori` user runtime agent (surface evidence) |
| Boot default | Generation selected for the next boot | System observer |

An atomic profile replacement does not make activation atomic. A Nix build does not prove a runtime change. A generation is not a data backup.

## Local service

Run `nori-desktop-config` as a rootless system service under the dedicated
`nori-desktop-settings` UID. Do not run the authority in the `nori` user
manager, and do not bind its lifetime to Hyprland or a client.

Display operations report unavailable when no matching `nori` session runtime
agent exists. The profile and job coordinator remain available independently.

The authority has two fixed Unix-domain socket paths beneath
`/run/nori-desktop-settings/`; do not add a TCP listener:

- `/run/nori-desktop-settings/backend.sock` is the private backend socket,
  owned by `nori-desktop-settings` and mode `0600`.
- `/run/nori-desktop-settings/public.sock` is the public ingress socket,
  mode `0660`, group-gated so the `nori` user can connect, and protected by
  `SO_PEERCRED`; ingress rejects every peer credential other than `nori`.

The fixed runtime directory is root-owned and provisioned so the authority can
create its sockets while group-authorized `nori` clients can traverse to public
ingress. Refuse unsafe pre-existing paths before binding. The public socket
cannot be mode `0600`: a `nori` client has a different UID from the dedicated
authority, so `0600` would prevent the client from reaching it. Group access
is only admission to ingress; `SO_PEERCRED` remains the caller-identity check.

Use a bounded framed protocol. Reject oversized frames, unknown fields,
unknown operations, and extra messages after one request.

The TypeScript protocol uses Effect Schema. The Nix-generated component schemas
remain the setting authority; Effect schemas define operations and job
lifecycles only.

Required operations are:

- Read the current snapshot.
- Preview a draft against an expected revision.
- Commit a validated draft through compare-and-swap.
- Start an apply for one exact revision.
- Read or watch an apply job.
- Read generated schemas and presentation metadata.
- Execute and manage saved commands through the same profile owner.

The existing `rice-saved-command` executable becomes a thin client of this
service. Quickshell and Vicinae use the same typed CLI bridge through public
ingress.

## Effect service boundaries

Use the repository's pinned TypeScript 7, Bun, and Effect v4 versions unless implementation research requires one coordinated update.

The portable program depends on these abstract services:

- `ProfileStore`: strict decoding, revision compare-and-swap, and durable replacement.
- `SchemaCatalog`: generated schema and presentation lookup.
- `NixEvaluator`: resolved output and impact preview.
- `NixBuilder`: one immutable build for a base source and profile revision.
- `SessionRuntime`: runtime-agent availability, reload-request delivery, and user-observation intake.
- `JobStore`: durable job state and bounded logs.
- `JobRunner`: serialized apply fibers with interruption and cleanup.
- `ActivationClient`: one named request to the privileged mechanism.
- `IpcServer`: socket ownership, framing, caller identity, and shutdown.

Concrete Bun, Nix, systemd, Hyprland, and filesystem behavior belongs in Layers at the composition root.

Do not read process environment inside domain services. Decode configuration once at the composition root and inject it.

Only one apply job can run at a time. Reads and previews can run concurrently against immutable revisions.

Profile commits and apply transitions share one mutation coordinator. Draft reads and previews can continue while an apply runs.

After a service crash, mark an unfinished job as interrupted and observe real state. Never resume activation from an assumed step.

## Preview and apply sequence

A change follows this order:

1. Client reads revision `R`.
2. Client submits a draft with expected revision `R`.
3. Service validates the generated input schema.
4. Nix evaluates the draft with the approved base source and pinned inputs.
5. Service returns the resolved setting and impact preview.
6. User authorizes the exact previewed revision.
7. Service commits revision `R+1` through compare-and-swap.
8. The build adapter realizes the exact base source plus profile revision.
9. The privileged mechanism authorizes and activates that exact result.
10. The `nori` session runtime agent reloads Waybar when required and submits unit and layer-surface observations as user-observed surface evidence.
11. The service observes active generation, boot default, and resolved profile baseline.

If validation or evaluation fails, no profile or runtime state changes.

If reload or observation fails after commit, desired state remains at `R+1`. The job reports `apply-failed` with actual observed state and a retry action.

If build fails, the active generation remains unchanged. Preserve desired state and diagnostics.

Activation can have partial live effects. Report the actual generation and unit state. Do not claim automatic transactional rollback.

If a newer desired revision exists after an older apply, report both identities. Never label the older active baseline as current desired state.

## Clean build source

Each preview and build uses an immutable tuple:

- Approved committed homelab source.
- Its locked inputs.
- Target system.
- Exact profile revision and content hash.

Never evaluate the operator's dirty checkout from the GUI.

The active system exposes an immutable store source as the approved base. The profile is decoded as JSON data and passed to a fixed Nix entrypoint.

Do not accept Nix source text, flake URLs, arbitrary command strings, or client-selected activation programs through the service protocol.

## Privileged activation

The rootless dedicated authority cannot activate a NixOS generation directly.

Add one narrow system mechanism protected by a namespaced polkit action. The
existing session already provides a polkit authentication agent. The mechanism
accepts an apply ID and expected profile revision. It does not accept an
arbitrary root command.

All activation attempts serialize through the fixed, root-owned lock
`/run/lock/nori-desktop-settings-activation.lock`. The lock is not an
authority-state file and is never user-writable.

The mechanism must:

1. Resolve the caller identity and active session.
2. Ask polkit to authorize the named activation operation for that caller.
3. Read the root-owned approved base source identity.
4. Read the exact dedicated-authority profile and job snapshot.
5. Strictly validate the revision, schema, ownership, expected content hash,
   canonical profile, and immutable identities.
6. Re-derive the system artifact from the approved source and JSON data.
7. Require that it matches the previewed artifact identity.
8. Run the fixed activation program for that artifact while holding the fixed
   activation lock.
9. Return actual activation and boot-default observations.

### Security-discovered dedicated-authority contract change

This frozen design remains implementation-authorized and workstation activation
remains operator-gated. Security review replaced the earlier proposed
user-manager/XDG-owned authority and single `0600` client socket with the
dedicated-authority contract in this document: persistent versioned state is
owned by `nori-desktop-settings` at `/var/lib/nori-desktop-settings/`, private
backend traffic uses its `0600` socket, and `nori` reaches the group-gated
`0660` public ingress only after `SO_PEERCRED` verification. This records an
authorized contract correction; it does not claim that the service or
workstation activation is live.

The authority stops a verified build at `awaiting_authorization`. The active
`nori` session runtime agent alone invokes the fixed polkit operation with an
apply ID and expected revision. The root helper re-reads the
dedicated-authority job and revision snapshot, validates their ownership, hash,
canonical profile, and immutable identities, then performs only the fixed
switch operation.

After the switch, the `nori` user runtime agent reloads and observes Waybar,
then submits its strict observation to the authority. The authority
independently reads active generation metadata and accepts that observation
only as user-observed surface evidence; it never treats it as activation
identity or claims cryptographic process identity for Waybar within the `nori`
UID. Failed or cancelled authorization durably fails that apply job. Retrying
requires a new apply job.

A user-selected store path alone is not an approved artifact. Activating
arbitrary user-built NixOS output would be equivalent to granting root.

## Client boundaries

### Desktop Settings

Add an independent Quickshell configuration and desktop entry. Do not place it inside Persona's patched source tree.

The first view uses generated common controls. For this milestone, it needs one enum selector and read-only policy rows.

The QML process invokes the typed CLI bridge. It does not parse or edit the profile file directly.

The view must show:

- Desired revision and value.
- Resolved value.
- Observed user-unit state and surface edge.
- Pending, running, failed, or active apply status.
- Read-only reasons.
- Validation, conflict, build, activation, and observation errors.

Closing the window does not cancel or hide the apply job.

### Vicinae

Generate one setting action from the component declaration. Search opens the generic Nori extension with the enum control.

The extension reads and writes through the same CLI bridge. It does not gain a separate settings database.

The launcher remains a replaceable client. Removing it leaves the profile and service CLI usable.

### Waybar runtime boundary

Waybar reads only the activated generated configuration. Neither client edits
Waybar files or sends reload signals directly.

After activation, the `nori` user runtime agent requests the supported
user-unit reload and observes both unit health and the actual layer surface.
It submits that observation to the authority as user-observed surface evidence,
not as cryptographic proof of a distinct Waybar process identity. The
authority keeps activation identity separate from this observation.

The unrelated blue-light toggle in Waybar remains unchanged.

## Invariants

- One Nix declaration owns the setting type, default, presentation, and apply class.
- One versioned profile owns user intent and saved commands.
- Input and output schemas are generated from evaluated options.
- Policy values are absent from writable input and present as read-only output.
- Settings and Vicinae read the same service snapshot through public ingress.
- The dedicated authority is the only profile, preview, and job-state writer.
- The `nori` client reaches only the fixed group-gated public socket; private
  backend traffic remains `0600` and inaccessible to that client.
- Public ingress admits the `nori` user only after `SO_PEERCRED` verification.
- Revision mismatch cannot overwrite a newer profile.
- Runtime observation never silently becomes desired intent or activation
  identity.
- Generated files are never authorities.
- A failed operation never reports success.
- Missing runtime or activation authority makes an action unavailable.
- Activation never accepts arbitrary commands, source, or artifacts.
- Existing Hyprland, UWSM, Persona, Waybar, and launcher ownership remains
  intact.

## Acceptance gates

These scenarios are required during implementation. They have not run for this specification.

### Schema generation

- Generate paired input and output definitions from the pilot Nix module.
- Confirm input accepts only `top` or `bottom` for `desktop.waybar.position`.
- Confirm output includes evaluated policy fields as read-only.
- Confirm another enum member fails without a profile write, build, activation, or Waybar reload.
- Confirm an unsupported writable Nix type fails generation with its option path.
- Confirm generated schema output has no undocumented handwritten TypeScript copy.

### Revision ownership

- Start with revision `R` in an isolated fixture that provisions the dedicated
  authority state root at `/var/lib/nori-desktop-settings/`.
- Confirm `profile.json`, `jobs/`, and `previews/` are owned by
  `nori-desktop-settings`, not by the `nori` user manager or an XDG path.
- Preview two edits from `R`.
- Commit the first edit as `R+1`.
- Confirm the second edit fails with a conflict and preserves `R+1`.
- Kill the service during replacement at controlled points.
- Confirm the old or new full document exists after restart, never a partial
  document.
- Crash during an apply and restart the service.
- Confirm the job becomes interrupted and the service observes real active
  state before any retry.

### Authority ingress and activation isolation

- Confirm authority state uses only `/var/lib/nori-desktop-settings/` and that
  the dedicated UID owns its profile, job, and preview state.
- Confirm the only authority sockets are the fixed
  `/run/nori-desktop-settings/backend.sock` (`0600`) and
  `/run/nori-desktop-settings/public.sock` (`0660`) paths.
- Confirm a `nori` client cannot connect to the private backend socket and
  public ingress rejects any peer whose `SO_PEERCRED` is not `nori`.
- Confirm concurrent activation attempts serialize through the root-owned
  `/run/lock/nori-desktop-settings-activation.lock`.

### Real desktop apply

In an isolated Hyprland session with the real Home Manager unit:

- Apply `bottom` and observe the real Waybar layer surface at the bottom edge.
- Apply `top` and observe the same surface return to the top edge.
- Confirm the unit remains active after each reload.
- Confirm Settings and Vicinae show the same desired and resolved value.
- Force reload failure and confirm desired, active, and observed states remain distinct.
- Retry after restoring the unit and confirm the mismatch clears.

Do not use reload exit status or a mocked systemctl result as proof. Inspect the actual compositor layer surface.

### Managed realization

In a disposable NixOS fixture:

- Evaluate and build from an immutable source plus one profile revision.
- Confirm the generated Waybar configuration contains the selected position.
- Confirm managed activation asks the `nori` user runtime agent to reload the real user unit after activation.
- Apply, reboot, and observe the selected surface edge.
- Reject a profile or artifact that does not match the previewed source and revision.
- Force a build failure and confirm the running generation remains active.
- Force an activation failure and report actual partial state without claiming rollback.

### Client journey

- Launch Desktop Settings independently of Persona and Vicinae.
- Change the enum and leave the window while apply continues.
- Reopen it and observe the durable job result.
- Open the generated Vicinae setting action and observe the same revision and value.
- Remove the launcher client in a fixture and perform the same read and edit through the CLI.

### Saved-command consolidation

- Create and execute the existing literal-argv acceptance command through the service-owned profile.
- Confirm generated Vicinae scripts remain disposable projections.
- Confirm no operation still writes `saved-commands.json`.
- Re-run the existing nonzero, shell-boundary, and privilege-wrapper scenarios.

### Repository gates

- Type-check the service and client packages with locked dependencies.
- Run focused Effect behavior tests for validation, conflicts, and persistence
  failure boundaries.
- Build generated schema drift checks.
- Run the real group-gated public-ingress CLI bridge and Settings journeys.
- Confirm the private `0600` backend socket rejects the `nori` client and the
  `0660` public socket accepts only a group-authorized peer whose
  `SO_PEERCRED` is `nori`.
- Build the exact workstation projection from a clean committed tree.

## Non-goals

- nixpkgs package search, install, removal, or update.
- General editing of arbitrary Nix options.
- A text editor for Nix expressions.
- Secret storage.
- Network or remote configuration APIs.
- Multiple users or remote hosts.
- Replacing Hyprland, UWSM, Persona, Waybar, Vicinae, or the notification system.
- Automatic rollback of application data or arbitrary commands.
- Activating the current workstation without separate operator authority.

## Migration map

- Add the component declaration beside the desktop composition boundary, not inside Persona.
- Adapt `users/nori/programs/desktop/waybar.nix` to consume the resolved pilot setting.
- Keep session ownership in `users/nori/programs/desktop/default.nix`.
- Extend `users/nori/programs/desktop/action-model.nix` only for generated setting-action metadata.
- Reject duplicate IDs instead of relying on Nix right-biased attribute merging.
- Extend `users/nori/programs/desktop/vicinae/extension/` with the generic setting control.
- Move saved-command persistence from `users/nori/programs/desktop/vicinae/saved-command/` into the shared service.
- Add the independent Quickshell Settings client outside `persona-quickshell/`.
- Keep integrated Home Manager composition in `lib/machines.nix`.

Before changing exported Nix options or TypeScript symbols, implementation must obtain fresh LSP references where a language server is available.

## Evidence boundary

This document specifies proposed behavior. No schema generation, Settings UI, service, build, activation, or runtime scenario has run.

Source inspection established the current service, action, session, launcher, and Home Manager ownership. It did not prove the proposed design.

## Primary sources

- Current Clan converter at reviewed commit: https://git.clan.lol/clan/clan-core/src/commit/424c8dd7a0ef3d5194e538e87174371d91cb2bbe/lib/jsonschema/default.nix
- Pinned Home Manager Waybar option and reload contract: https://github.com/nix-community/home-manager/blob/e4345d5ae8aa1def34378d2a60ac5e6e4c8fd7c1/modules/programs/waybar.nix
- NixOS activation ordering and dry activation: https://github.com/NixOS/nixpkgs/blob/master/nixos/doc/manual/development/what-happens-during-a-system-switch.chapter.md
- Polkit mechanism and subject model: https://www.freedesktop.org/software/polkit/docs/latest/polkit.8.html
- Quickshell toolkit and live reload: https://quickshell.org/

Repository anchors were read from the current working tree. Reread them before implementation because the tree contains concurrent work.
