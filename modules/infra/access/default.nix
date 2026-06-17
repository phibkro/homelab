_:

/**
  Access concern — audience access (IAM).

  Distinct from "capabilities" (what services can DO on the
  machine): access covers the inbound direction — who can REACH
  the service. PaaS analogue: IAM, ACLs, API gateway policies.

  `authelia.nix` carries the Authelia daemon — OIDC provider for
  the family-tier audience. It reads `config.nori.lanRoutes.<X>.
  audience` + `.oidc` from `modules/infra/networking/default.nix`
  to assemble its client list at runtime.

  Future expansion: audience policy assertions (e.g. "no public
  audience without explicit operator approval") would land here as
  schema additions or assertion modules.

  See `docs/specs/2026-06-17-modules-as-root-restructure.md` § The
  two access concerns for the audience-vs-capabilities cut.
*/
{
  imports = [ ./authelia.nix ];
}
