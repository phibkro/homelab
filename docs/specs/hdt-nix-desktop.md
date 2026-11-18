# Nix-packaged HDT desktop integration

2026-11-15. Frozen for review.

## Goal

Replace the checkout's devenv service with the published HDT flake's Home Manager module. Register the desktop application in Vicinae and preserve the existing mutable data directory.

## Constraints

Pin the external source commit. Keep the current Steam prefix, account data, HDT installation, and Proton Experimental selection. Preserve unrelated operator work. No full dirty-tree machine activation or game restart.

## Acceptance and evidence

The module evaluates with no failed Home Manager assertions. Its generated desktop file passes desktop-file-validate. Its generated service runs the Nix-packaged watcher and derives all runtime paths from the package. HDT loads native CLR and exports advancing control snapshots after the isolated restart. The overlay origin matches the game. The game process remains unchanged.

Vicinae lists Hearthstone Deck Tracker. Launching the registered application focuses the existing tracker without a duplicate. The desktop action's restart command is tested. The menu item itself is not clicked through the UI.

The focused live activation used the actual generated unit and application entry. A full machine rebuild, fresh login, and stable Proton comparison remain untested. The previous service and module are retained in the project's private recovery directory.

## Verification

The external flake's package build and 17 tests pass. The homelab's required staged-snapshot checks gate this integration commit. The source pin identifies the tested implementation. Later documentation-only changes in the external repository do not change its package output.
