#!/usr/bin/env bash
set -euo pipefail

# The deployed template emits one `host` matcher per route. Read the running
# container's Caddyfile on stdin and project those exact matcher arguments.
awk '
  $1 == "host" {
    for (field = 2; field <= NF; field++) {
      print $field
    }
  }
'
