# Genexis JUCI API reference

## Transport

The observed Genexis firmware serves an Angular JUCI client. It opens a
WebSocket at the current web origin with subprotocol `ubus-json`:

```text
http://192.168.1.1/  -> ws://192.168.1.1/
https://192.168.1.1/ -> wss://192.168.1.1/
```

JUCI discovers methods dynamically with JSON-RPC method `list`. Do not treat
this reference as a firmware-independent exhaustive API.

## JSON-RPC envelope

Ordinary UBUS calls use:

```json
{
  "jsonrpc": "2.0",
  "method": "call",
  "params": ["<32-hex-session-id>", "<object>", "<method>", {}],
  "id": 1
}
```

Responses use a UBUS result array. Status `0` means success; status `6` was
observed for permission denied. Treat every nonzero status as failure unless a
procedure explicitly and safely expects it.

Method discovery uses:

```json
{
  "jsonrpc": "2.0",
  "method": "list",
  "params": ["<session-id>", "*"],
  "id": 1
}
```

## Authentication lifecycle

The browser calls `session.login` with username/password and stores the returned
`ubus_rpc_session` as local-storage key `sid`. This skill does not accept a
password or call login. The operator hands over a valid session ID, and the
executor ends every attempt with:

```json
{
  "jsonrpc": "2.0",
  "method": "call",
  "params": ["<session-id>", "session", "destroy", {}],
  "id": 99
}
```

Destroying the handed-over session may log the operator's browser out.

## Observed core objects

| Object | Observed methods | Policy floor |
|---|---|---|
| `session` | `login`, `list`, `destroy` | `list`: sensitive; login/destroy reserved |
| `uci` | `configs`, `get`, `add`, `set`, `delete`, `order`, `commit`, `rollback` | reads sensitive; writes mutation |
| `juci.unauthenticated` | `username`, `autocomplete` | harmless read |
| `juci.firewall` | `excluded_ports` | sensitive read |

Firmware modules also surface service-specific objects for firewall, network,
DHCP/DNS, wireless, DDNS, UPnP, diagnostics, system upgrade, backup, IPTV,
voice, USB, and vendor extensions. Discover and review their signatures before
use. Unknown calls are critical by default.

## UCI call shapes

Read sections:

```json
{"config":"firewall","type":"redirect"}
```

Add an anonymous section:

```json
{
  "config": "firewall",
  "type": "redirect",
  "values": {
    "name": "homelab_media_https",
    "enabled": "1",
    "src": "wan",
    "dest": "lan",
    "target": "DNAT",
    "proto": "tcp",
    "src_dport": "443",
    "dest_ip": "192.168.1.225",
    "dest_port": "443",
    "reflection": "0"
  }
}
```

`uci.add` returns a generated section name. Later actions may reference it with
the executor expression `${actions.<action-id>.section}`.

Update, delete, and commit:

```json
{"config":"firewall","section":"cfg123456","values":{"enabled":"0"}}
{"config":"firewall","section":"cfg123456"}
{"config":"firewall"}
```

JUCI's port-forward page calls `uci.add` immediately but relies on a separate
global Apply action to call `uci.commit`. A visible rule can therefore be only
staged. Always commit explicitly and read the full section type back through a
fresh RPC call.

## Firewall redirect fields

| Field | Meaning |
|---|---|
| `src` | Ingress firewall zone, normally `wan` |
| `dest` | Destination zone, normally `lan` |
| `src_ip` | Allowed remote source address—not the internal target |
| `src_dport` | Public destination port or range |
| `dest_ip` | Internal destination address |
| `dest_port` | Internal destination port or range |
| `proto` | `tcp`, `udp`, or firmware-specific combined value |
| `target` | `DNAT` for a port forward |
| `reflection` | NAT loopback/hairpin toggle |

The observed JUCI failure populated `src_ip` with the selected internal device,
causing every real internet client to be rejected. Never derive `src_ip` from
the destination device picker.
