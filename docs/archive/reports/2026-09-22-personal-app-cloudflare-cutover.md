# Personal application Cloudflare cutover — September 22, 2026

## Scope

This change moved four personal applications to Cloudflare through their own Alchemy v2 programs.

| Application | Production URL | Source revision | Cloudflare resources |
|---|---|---|---|
| Drinks | `https://drinks.phibkro.org/` | `e69341d0adc5a4200e30d91092d8cf351ac10ea1` | Static site, API Worker, and adopted D1 database |
| Filmder | `https://filmder.phibkro.org/` | `6839459fdc1158eecbaeac73bcb769cc92e46ea2` | Static site Worker and same-origin TMDB proxy |
| Finnbydel | `https://finnbydel.phibkro.org/` | `09b6483c1d097f5b5adbf85107f8226b91a8d9ae` | Static site, API Worker, and adopted D1 database |
| Heim | `https://me.phibkro.org/` | `6abe4bd713d1ab75236136b76b3150bc10d44530` | Static site Worker |

Alchemy retained the existing Drinks and Finnbydel D1 databases. The deployment did not replace their production data.

## Production acceptance

The browser loaded all four public applications from their final hostnames. The visible Drinks list contained production cocktail data.

Filmder displayed the movie browser and loaded poster images. Its same-origin TMDB endpoint returned HTTP 200 with 20 results.

Finnbydel displayed the city selector. Its production API returned HTTP 200 for `Karl Johans gate 1` in Oslo.

Heim displayed the production portfolio at `me.phibkro.org`. The HTML title and visible identity matched the application.

After deployment, each Alchemy production plan reported `Plan: no changes`. This result covered all declared resources in each application stack.

The default automation user agent received HTTP 403 from three Cloudflare sites. A standard Chrome user agent loaded the same sites successfully.

Direct HTTP checks also returned HTTP 200 for Filmder, Finnbydel, and Heim. Cloudflare served each response.

## Local runtime retirement

The homelab source revision was `b6465353c4646a1ce93a8162f617954ed19607c6` before the retirement commit.

The deployment planner selected Adelie before Pi. The new Adelie system was:

`/nix/store/3bwdf11p1jh263zv8h50chxn5w0w6lhh-nixos-system-adelie-26.11.20260910.8ce4ef6`

Adelie stopped and removed these units:

- `filmder-serve.service`
- `filmder-static.service`
- `heim-serve.service`

Adelie also removed the Filmder and Heim system accounts. It removed `tmdb-token` and the rendered `filmder-env` secret.

The host remained in the `running` state with no failed units. Attic and its cache watcher remained active.

Ports 9092 and 9094 no longer accepted connections. The reproducible source and build directories under `/var/lib/filmder` and `/var/lib/heim` were removed.

The Pi deployment removed both private Caddy routes. The deployed Caddy configuration contains no `filmder` or `heim` route.

The Pi deployment completed with no failed or unreachable tasks. The final Pi check passed.

The service removal reduced the Glance bookmark-group count from five to four. The Pi contract now checks the current count.

## Repository state and limits

All five repositories were clean after the changes. No Git repository was pushed.

The local application branches remain ahead of their cached `origin/main` references. The Cloudflare deployments used these local committed revisions.

Sentry projects and DSNs were not provisioned. Drinks and Filmder contain dormant Sentry initialization that requires a production DSN.
