_:

# Vaultwarden — access concern.
#
# Route declaration is lifted outside the activation gate (no mkIf)
# so any host importing this module sees vault.nori.lan in its
# lanRoutes registry — needed for the proxy host (pi/aurora/
# workstation, decided by host config) to know how to route + DNS
# even if the actual vaultwarden service runs elsewhere. `runsOn`
# tells the generators where the backend lives; lan-route resolves
# to 127.0.0.1 on that host, tailnet IP on others.
#
# `/alive` returns "1" on healthy (Vaultwarden's health endpoint).

{
  nori.lanRoutes.vault = {
    port = 8222;
    runsOn = "aurora";
    exposeOnTailnet = true;
    monitor = {
      path = "/alive";
    };
    audience = "family";
    oidc = {
      clientName = "Vaultwarden";
      redirectPath = "/identity/connect/oidc-signin";
      secretEnvName = "SSO_CLIENT_SECRET";
      # `openid` (always implicit) + the three standard claims +
      # offline_access for refresh tokens. The Authelia client must
      # list `offline_access` for the request to be allowed; this
      # matches `services.vaultwarden.config.SSO_SCOPES` in default.nix.
      scopes = [
        "openid"
        "profile"
        "email"
        "groups"
        "offline_access"
      ];
    };
  };
}
