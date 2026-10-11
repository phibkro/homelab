{ config, ... }:

let
  listeners = config.nori.inventory.workloads.unifi.listeners;
in
{
  services.unifi = {
    enable = true;
    # The NixOS module opens ports globally; keep all firewall policy local.
    openFirewall = false;
  };

  networking.firewall.interfaces.tailscale0.allowedTCPPorts = [ listeners.ui.port ];

  # UniFi reads this port from system.properties, not JVM -D properties.
  # Preserve application-owned settings and atomically replace only this key.
  systemd.services.unifi.preStart = ''
    mkdir -p data
    properties=data/system.properties
    managed=$(mktemp data/.system.properties.XXXXXX)
    trap 'rm -f "$managed"' EXIT
    if [ -f "$properties" ]; then
      sed '/^[[:space:]]*unifi\.https\.port\([[:space:]:=]\|$\)/d' "$properties" > "$managed"
    fi
    printf '\nunifi.https.port=%s\n' '${toString listeners.ui.port}' >> "$managed"
    chmod 600 "$managed"
    mv -f "$managed" "$properties"
    trap - EXIT
  '';

  # nixpkgs' unit already applies strict systemd hardening and scopes its
  # StateDirectory to /var/lib/unifi. Register it with the local FS policy too.
  nori.harden.unifi = { };

  # Preserve UniFi state and native application exports, but do not hot-copy
  # live MongoDB files: filesystem snapshots are not a consistent DB backup.
  # UniFi documents software autobackups at {data.dir}/backup/autobackup
  # (https://help.ui.com/hc/en-us/articles/205202580-Explaining-the-UniFi-system-properties-File).
  # The NixOS module's removed dataDir notice maps this deployment's data
  # directory to /var/lib/unifi/data.
  # Enable/schedule autobackups in the controller UI.
  nori.backups.unifi = {
    include = [ "/var/lib/unifi" ];
    exclude = [ "/var/lib/unifi/data/db" ];
    tier = "service";
  };
}
