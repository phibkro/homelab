# User changes

Start with [the shared guide](../../AGENTS.md). `src/users/nori/` owns the operator
identity, Home Manager composition entry point and program implementations.
Reusable Home Manager compositions live under `src/profiles/home/`; they import
implementations from `src/users/nori/programs/`.

Keep host-specific package, resource-limit and `/srv/nori` link policy in
`src/users/nori/workstation.nix`. Keep account defaults and selected profiles in
`src/users/nori/home.nix`, and user declarations/authorized keys in
`src/users/nori/identity.nix`. Preserve secret ownership and out-of-store link
boundaries when editing these files.
