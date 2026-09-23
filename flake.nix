{
  description = "nori infrastructure (NixOS) — workstation and future lab hosts";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    nixos-hardware.url = "github:NixOS/nixos-hardware/master";

    /*
      flake-parts — module system FOR flakes. Same composition shape
      (one input → multiple outputs) that `nori.<X>` modules use at the
      NixOS layer, applied to the flake-output layer. Lets each check /
      package / devshell live in its own file with a typed interface.
      Eval doc: docs/archive/plans/2026-06-21-dendritic-evaluation.md.
    */
    flake-parts.url = "github:hercules-ci/flake-parts";
    flake-parts.inputs.nixpkgs-lib.follows = "nixpkgs";

    /*
      nixpkgs master — used ONLY for cherry-picking individual packages
      whose nixos-unstable channel cut lags far behind upstream. Don't
      mass-overlay from this; resolve specific lags one package at a
      time. Currently consumed by:
        src/profiles/desktop/nixos/apps.nix → zed-editor (nixos-unstable shipping
          v0.232.3 as of 2026-05-07, master shipping v1.1.6; months of
          Linux/Wayland/file-watcher fixes in the gap)
    */
    nixpkgs-master.url = "github:NixOS/nixpkgs/master";

    /*
      Numtide's daily-updated, CI-tested agent package set. Keep its own
      nixpkgs pin: upstream recommends this direct-package path so package and
      dependency versions advance together and remain eligible for its cache.
    */
    llm-agents.url = "github:numtide/llm-agents.nix";

    disko.url = "github:nix-community/disko/latest";
    disko.inputs.nixpkgs.follows = "nixpkgs";

    sops-nix.url = "github:Mic92/sops-nix";
    sops-nix.inputs.nixpkgs.follows = "nixpkgs";

    # Home Manager follows unstable with the NixOS hosts.
    home-manager.url = "github:nix-community/home-manager";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";

    /*
      Zen browser. Not in nixpkgs; consumed via upstream community flake.
      `.default` tracks rolling Twilight; pivot to `.beta` or `.specific`
      if Twilight churn becomes annoying.
    */
    zen-browser.url = "github:0xc000022070/zen-browser-flake";
    zen-browser.inputs.nixpkgs.follows = "nixpkgs";

    /*
      snappy-switcher — Hyprland alt-tab overlay. Not in nixpkgs;
      upstream ships a flake. Bindings + daemon autostart live in
      src/users/nori/programs/desktop/hypr-rice/hyprland.lua (ALT+Tab MRU global, SUPER+Tab
      workspace-local).
    */
    snappy-switcher.url = "github:OpalAayan/snappy-switcher";
    snappy-switcher.inputs.nixpkgs.follows = "nixpkgs";

    /*
      Persona — Quickshell presentation layer for the workstation. Persona
      itself and its optional Cava visualizer are pinned source trees; the
      Home Manager module builds both against this flake's Qt/nixpkgs closure.
    */
    persona-quickshell.url = "git+https://github.com/Yujonpradhananga/Persona-Quickshell";
    persona-quickshell.flake = false;
    persona-cava.url = "git+https://github.com/Yujonpradhananga/Qt6-Cava-plugin";
    persona-cava.flake = false;

    /*
      Stylix — single-input system-wide theming. Same
      Reader+collected-Writer shape as the lab's `nori.<X>` effect
      family — fits cleanly. Workstation imports the NixOS module
      via src/profiles/desktop/nixos/stylix.nix.
    */
    stylix.url = "github:danth/stylix";
    stylix.inputs.nixpkgs.follows = "nixpkgs";

    tilth.url = "github:jahala/tilth";
    tilth.inputs.nixpkgs.follows = "nixpkgs";
    stacklit-src.url = "github:glincker/stacklit";
    stacklit-src.flake = false;

    /*
      Herdr — terminal multiplexer + socket control plane for coding agents.
      The package and its Claude skill let a first-party Fable lead dispatch
      external Codex CLI workers without pretending one Claude Code process
      can switch provider endpoints per subagent.
    */
    herdr.url = "github:ogulcancelik/herdr/v0.7.5";
    herdr.inputs.nixpkgs.follows = "nixpkgs";

    /*
      ClaudeX — OpenAI Codex models behind Claude Code's harness. The
      external flake owns the pinned proxy package, hardened user service,
      model aliases, acceptance prompt, and audit commands. This repo only
      enables its Home Manager module; runtime OAuth state remains mutable.
    */
    claudex.url = "github:phibkro/claudex";
    claudex.inputs.nixpkgs.follows = "nixpkgs";
    claudex.inputs.home-manager.follows = "home-manager";

    /*
      pagu — the consolidated box + gate product. Consumes the gate and its
      co-packaged `pagu-box` compatibility PEP from one revision. Advance the
      pin deliberately.
    */
    pagu.url = "github:phibkro/pagu/a17fb721522b2081275efb2cbed2a92422fa4ba1";
    pagu.inputs.nixpkgs.follows = "nixpkgs";

    /*
      Foldkit — Effect-based Elm-architecture frontend framework. Pinned as
      a plain source tree so agent skills (foldkit, generate-program,
      audit-program) can be mirrored from skills/ into every harness surface
      without evaluating the upstream repo. Bump the pin deliberately.
    */
    foldkit-src.url = "github:foldkit/foldkit/07b0f05a3f5a866be3359b53fee05b20c81268f7";
    foldkit-src.flake = false;

    /*
      Effect-TS/skills — upstream agent skills for Effect work (effect-ts
      repo-onboarding guidance + effect-v3-to-v4 migration workflow).
      Same source-tree consumption as foldkit-src.
    */
    effect-skills.url = "github:Effect-TS/skills/28822c9e19998876a6b0e0d97877442012ed4391";
    effect-skills.flake = false;

    /*
      Clan Core — source-only access to its Nix option → JSON Schema
      converter. Do not evaluate Clan's fleet flake or import its service
      model; the desktop component generator consumes only clanLib.jsonschema.
    */
    clan-core-src.url = "https://git.clan.lol/clan/clan-core/archive/424c8dd7a0ef3d5194e538e87174371d91cb2bbe.tar.gz";
    clan-core-src.flake = false;
    microvm.url = "git+https://github.com/microvm-nix/microvm.nix.git?rev=1b99da49e9d1c8f15fd4911f7b8d2c4375758dcd";
    microvm.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs =
    inputs@{ flake-parts, ... }:
    flake-parts.lib.mkFlake { inherit inputs; } {
      systems = [ "x86_64-linux" ];

      # Per-output flake-parts modules — each file declares its own
      # perSystem or flake fragment. Adding a new output = new file +
      # one line here (or auto-discovery via haumea if the tree grows).
      imports = [
        ./src/lib/flake-parts/formatter.nix
        ./src/lib/flake-parts/devshell.nix
        ./src/lib/flake-parts/machines.nix
        ./src/lib/flake-parts/packages/docs-backups.nix
        ./src/lib/flake-parts/packages/docs-recovery-evidence.nix
        ./src/lib/flake-parts/packages/docs-fs.nix
        ./src/lib/flake-parts/packages/inventory.nix
        ./src/lib/flake-parts/packages/operator-view.nix
        ./src/lib/flake-parts/packages/docs-routes.nix
        ./src/lib/flake-parts/packages/docs-topology.nix
        ./src/lib/flake-parts/packages/docs-capabilities.nix
        ./src/lib/flake-parts/checks/conventions.nix
        ./src/lib/flake-parts/checks/lint.nix
        ./src/lib/flake-parts/checks/e2e.nix
        ./src/lib/flake-parts/checks/eval.nix
      ];

    };
}
