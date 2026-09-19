---
summary: Replace the Fuzzel action palette with Vicinae and add persistent saved commands.
date: 2026-09-12
status: implemented
---

# Vicinae launcher and saved commands

## Goal

`SUPER+SPACE` opens Vicinae as the desktop launcher.

Vicinae shows installed applications and each existing rice action in root search. Existing direct key bindings keep their current behavior.

A user can create a saved command in Vicinae without opening a terminal. The saved title appears in root search and remains after login.

## User journey

1. Press `SUPER+SPACE`.
2. Search for an installed application or an existing rice action.
3. Run the selected item.
4. Open `Create Command`.
5. Select structured argv mode or explicit shell-script mode.
6. Enter a title, executable, arguments, optional working directory, up to three parameters, and output mode.
7. Save the command.
8. Search for the saved title in root search.
9. Enter parameter values and run the command.
10. Read its output or failure in Vicinae.
11. Log out and in, then find the saved command again.

## Invariants

- `nori.desktop.actions` is the only evaluated action catalog.
- `rice-command` remains the only executor for existing rice actions.
- Vicinae entries and direct Hyprland bindings derive from the same catalog.
- Existing action IDs, labels, keywords, argv, direct bindings, and confirmation behavior do not change.
- Generated Vicinae scripts dispatch one exact action ID. They do not copy action execution logic.
- Saved argv commands store an executable and an argument array. User parameters replace named placeholders inside existing arguments. They never create shell syntax or additional arguments.
- Shell-script mode is explicit user-authored code. It runs with normal user authority.
- Saved-command state has one owner and one versioned document. Generated scripts are disposable projections.
- Mutating saved-command operations hold an exclusive file lock and replace files atomically.
- A failed write keeps the previous profile and script projection.
- A saved command cannot request privileged execution through `sudo` or another privilege wrapper.
- Vicinae starts and stops with `hyprland-session.target`.
- Removing Vicinae does not remove the action catalog, executor, or direct bindings.

## Data contract

The profile is JSON at `$XDG_CONFIG_HOME/nori-desktop/profile.json`.

The root object contains `formatVersion`, `revision`, `components`, and `savedCommands`.

- A stable ID in the `user.*` namespace.
- A title and output mode.
- Zero to three parameter declarations.
- An optional absolute working directory.
- Either structured argv execution or explicit shell source.

Structured argv execution contains one executable and an ordered argument list. Arguments can contain `{{parameter-name}}` placeholders.

Shell execution contains source text. Parameter values are positional shell arguments. The shell source cannot claim reproducible execution.

The service rejects unknown fields, duplicate parameter names, unknown placeholders, relative working directories, empty executables, unsupported output modes, and privilege wrappers.

## Ownership and files

- `users/nori/programs/desktop/action-model.nix` declares the internal Home Manager action contract.
- `users/nori/programs/desktop/hypr-rice/runtime.nix` defines existing actions, the dispatcher, and direct bindings.
- `users/nori/programs/desktop/vicinae/default.nix` owns Vicinae integration and generated script entries.
- `users/nori/programs/desktop/settings-service/` owns the Effect/Bun profile service, saved-command state, and CLI.
- `users/nori/programs/desktop/vicinae/extension/` owns the Vicinae create-command form.
- `users/nori/programs/desktop/default.nix` composes these modules and keeps session ownership.

The old `rice-palette` and `rice-launch` frontend files are removed after Vicinae passes the replacement journey. Focused Fuzzel interfaces, such as layout prompts and the key-binding sheet, remain.

## Selected implementation

Use the pinned Home Manager `programs.vicinae` module and `config.lib.vicinae.mkExtension`. Do not add a Vicinae flake input or fork its runtime.

Use generated Vicinae script commands for existing and saved actions. Use one React extension only for the create-command form.

Use TypeScript 7, Bun, and Effect v4 for saved-command validation and execution. The Vicinae extension uses its required Node runtime and `@vicinae/api`.

Use a typed CLI bridge for this milestone. A resident Unix-socket service is not required until a background job or shared live-state lifecycle needs one.

## Non-goals

- Settings UI, nixpkgs store, rollback UI, or a general component SDK.
- Replacing Hyprland, UWSM, Persona, Waybar, Hyprlock, or notification services.
- Replacing focused Fuzzel prompts.
- Installing packages for saved commands.
- Treating saved commands as root-authorized actions.
- Activating the workstation without separate operator authority.

## Acceptance gates

### Generated action projection

- Every catalog action with `palette = true` has one executable Vicinae script.
- Each generated script contains its catalog title, description, keywords, and output mode.
- Each script dispatches only its exact ID through `rice-command`.
- Direct bindings in generated Hyprland Lua still dispatch the same IDs.
- No private rice desktop entries or Fuzzel XDG overlay remain.

### Saved argv command

In disposable XDG directories, create a command that runs Nix-provided `printf`.

Pass the literal argument `hello; touch /tmp/should-not-exist` through a parameter. Output must contain that exact text, exit status must be zero, and the file must not exist.

The saved script must use a Vicinae argument directive and must remain after a new CLI process starts.

### Failure reporting

Create a command that writes a message to standard error and exits nonzero. The generated script must preserve the exit status and error output. Vicinae must not report success.

### Shell boundary

Create an explicit shell command and verify that positional arguments reach it. Reject the same shell source when submitted as an argv executable.

Reject `sudo`, `doas`, `pkexec`, and equivalent direct privilege-wrapper executables in saved commands.

### Launcher journey

In an isolated Wayland session, start the built Vicinae service and open it. Search and execute one generated rice action and one saved command. Confirm the launcher can also find a real desktop application.

### Repository gates

- The Vicinae extension builds and type-checks against the locked dependencies.
- The saved-command package type-checks and its behavioral journey passes.
- The focused Nix checks build the exact workstation projection.
- Existing Hyprland Lua and direct-binding checks pass.

## Evidence boundary

These gates describe required behavior. Repository checks, live activation, and the isolated launcher journey provide the evidence listed below. Logout and login persistence still require a separate journey.

Implemented and verified on 2026-09-12, then activated on 2026-09-20:

- The saved-command type check and five behavioral tests passed.
- The extension type check passed.
- The launcher projection and existing Hyprland layout checks built.
- The built launcher passed the private headless-Sway journey.
- A clean committed `main` activated on the workstation with `just rebuild`.
- The live settings service returned its state, the Vicinae user service stayed active, and `vicinae-launcher-live-test` passed.

The activation did not include a logout and login cycle. Login persistence remains unverified.
