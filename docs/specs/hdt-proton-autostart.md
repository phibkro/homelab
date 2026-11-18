# Start HDT automatically with Hearthstone

Goal: the workstation's Hyprland session starts the existing project-owned HDT compatibility launcher when the operator opens Hearthstone through Steam. The operator should not type a launch command.

Contract: keep the Steam ID, matching Proton/prefix selection, process lock and compatibility behavior in the [HDT project](https://github.com/phibkro/hdt-proton-hyprland). Home Manager owns one session-bound user-service declaration. Never launch, stop, focus or change the game; reuse an already-running tracker and avoid restart loops after a manual HDT exit. No credentials or game data enter this repository.

Implementation: import the workstation-only program module; run the project's pinned devenv monitor from the existing checkout. Condition startup on the project's local configuration. Adopt only the generated interim unit link for this named service on the next Home Manager activation. The project checkout is an explicit runtime prerequisite, rather than an embedded HDT installer or prefix copy.

Verification: the generated unit was derived from this declaration and activated independently of unrelated homelab edits. On the real desktop it left an existing HDT alone, rejected a second monitor via its lock, and launched HDT with native CLR, working overlay/input and successful updater check alongside the unchanged game process. The service is enabled and active. Unit syntax and Nix parsing passed. Fresh login/new game transition and a full machine rebuild remain untested; repository checks are recorded in the PR. No full NixOS activation is part of this publication.
