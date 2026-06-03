---
name: gotcha-gatus-ntfy-provider-shape
description: USE WHEN configuring Gatus ntfy alerting — `topic` and `url` are SEPARATE fields, NOT a combined `https://ntfy.sh/<channel>` URL. If you put topic in URL, Gatus silently disables the provider ("Ignoring provider=ntfy due to error=topic not set") — no runtime errors, alerts just don't send.
---

# Gatus ntfy provider: `topic` and `url` are separate

Easy mistake: putting topic in URL like `https://ntfy.sh/<channel>`. Gatus's ntfy provider expects them as separate fields:

```nix
alerting.ntfy = {
  url = "https://ntfy.sh";
  topic = "\${NTFY_CHANNEL}";  # via env substitution
  priority = 4;
};
```

If you put topic in URL, Gatus silently disables the provider (`Ignoring provider=ntfy due to error=topic not set`) — no errors at runtime, alerts just don't send.
