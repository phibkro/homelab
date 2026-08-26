{
  description = "nori infrastructure (NixOS) — workstation and future lab hosts";
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    /*
      A stable pin kept only for packages that need one — currently just
      handbrake (modules/home/profiles/creative/video.nix). Still on the
      26.05 *darwin* branch, a leftover of the retired Intel Mac
      (ADR-0006, superseded); the branch carries every platform, so this is
      cosmetically wrong rather than broken. Repointing it re-resolves
      handbrake, so that is a deliberate bump, not a cleanup rider.
    */
    nixpkgs-stable.url = "github:NixOS/nixpkgs/nixpkgs-26.05-darwin";
    nixos-hardware.url = "github:NixOS/nixos-hardware/master";

    /*
      flake-parts — module system FOR flakes. Same composition shape
      (one input → multiple outputs) that `nori.<X>` modules use at the
      NixOS layer, applied to the flake-output layer. Lets each check /
      package / devshell live in its own file with a typed interface.
      Eval doc: docs/plans/2026-06-21-dendritic-evaluation.md.
    */
    flake-parts.url = "github:hercules-ci/flake-parts";
    flake-parts.inputs.nixpkgs-lib.follows = "nixpkgs";

    /*
      nixpkgs master — used ONLY for cherry-picking individual packages
      whose nixos-unstable channel cut lags far behind upstream. Don't
      mass-overlay from this; resolve specific lags one package at a
      time. Currently consumed by:
        modules/machines/desktop/apps.nix → zed-editor (nixos-unstable shipping
          v0.232.3 as of 2026-05-07, master shipping v1.1.6; months of
          Linux/Wayland/file-watcher fixes in the gap)
    */
    nixpkgs-master.url = "github:NixOS/nixpkgs/master";

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
      modules/home/desktop/hypr-rice/hyprland.lua (ALT+Tab MRU global, SUPER+Tab
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
      via modules/machines/desktop/stylix.nix.
    */
    stylix.url = "github:danth/stylix";
    stylix.inputs.nixpkgs.follows = "nixpkgs";

    /*
      nix-community/impermanence — "erase your darlings" mechanism.
      Retained for future opt-in host use; the former quarantine host used
      btrfs rollback rather than a tmpfs root, demonstrating that the module
      is filesystem-agnostic.
    */
    impermanence.url = "github:nix-community/impermanence";

    tilth.url = "github:jahala/tilth";
    tilth.inputs.nixpkgs.follows = "nixpkgs";
    rtk-src.url = "github:rtk-ai/rtk";
    rtk-src.flake = false;
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
    pagu.url = "github:phibkro/pagu";
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
  };

  outputs =
    inputs@{ flake-parts, ... }:
    flake-parts.lib.mkFlake { inherit inputs; } {
      systems = [ "x86_64-linux" ];

      # Per-output flake-parts modules — each file declares its own
      # perSystem or flake fragment. Adding a new output = new file +
      # one line here (or auto-discovery via haumea if the tree grows).
      imports = [
        ./flake-parts/formatter.nix
        ./flake-parts/devshell.nix
        ./flake-parts/machines.nix
        ./flake-parts/packages/docs-backups.nix
        ./flake-parts/packages/docs-fs.nix
        ./flake-parts/packages/docs-replicas.nix
        ./flake-parts/packages/inventory.nix
        ./flake-parts/packages/docs-helpers.nix
        ./flake-parts/checks/conventions.nix
        ./flake-parts/checks/lint.nix
        ./flake-parts/checks/e2e.nix
        ./flake-parts/checks/eval.nix
      ];

    };
}
