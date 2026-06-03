---
name: gotcha-pocketbase-oauth-per-collection
description: USE WHEN configuring OAuth2 in PocketBase 0.36+ (e.g. for Beszel's `users` collection) — OAuth moved from global system settings to per-collection. Path: Collections → users → ⚙ Options → OAuth2 tab. The "Auth with OAuth2" menu overlay stays greyed out until OAuth2 is enabled for the collection.
---

# PocketBase 0.36 OAuth2: per-collection, not global

PocketBase moved OAuth provider configuration from system-wide settings to per-collection (each auth-type collection has its own OAuth config). For Beszel, the auth collection is `users`. Path: Collections (database icon) → users → ⚙ Options → OAuth2 tab. Or via the "Auth with OAuth2" overlay menu (which is greyed out until OAuth2 is enabled for the collection).
