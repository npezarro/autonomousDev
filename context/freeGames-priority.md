# freeGames — Priority Work (2026-03-28)

This repo needs focused attention. The free game discovery and auto-claim system has several issues to fix.

## Current Errors (from Discord #free-game-claims)

### 1. Epic Games Playwright claim — CAPTCHA (EXPECTED, LOW PRIORITY)
The direct Playwright login hits Epic's puzzle CAPTCHA every time. This is handled by the separate `epic-claimer` PM2 process (claabs/epicgames-freegames-node) which uses device code auth. The Playwright `src/claim/epic.js` module will always fail — consider skipping the Playwright Epic claim attempt entirely since `epic-claimer` handles it.

### 2. Epic Checkout CAPTCHA (NEEDS FIX)
The `epic-checkout` server (port 3100) receives checkout URLs from `epic-claimer` and tries to complete them via Playwright, but Epic's checkout also requires login which hits CAPTCHA. The checkout server needs to use the device auth token from `epic-claimer` instead of Playwright login. Look at Epic's purchase API — the checkout may be completable via API call with the bearer token from `config/device-auths.json` on the VM at `~/repos/epic-free-claimer/config/device-auths.json`.

### 3. GOG 2FA email code not found (NEEDS FIX)
GOG sends a 4-digit security code to REDACTED_EMAIL. The `pollEmailCode("noreply@gog.com", /\b(\d{4})\b/, 60)` call isn't finding the code. Possible issues:
- Wrong sender address — check what email address GOG actually sends from
- Code pattern doesn't match — the code might be embedded in HTML differently
- Timing — 60s might not be enough, or the email arrives in a different Gmail folder
- Test by triggering a GOG login and checking Gmail via IMAP for the actual email

### 4. Amazon Prime — "No new games" (WORKING CORRECTLY)
Amazon successfully logs in + 2FA but finds no games to claim because they were already claimed. This is correct behavior.

### 5. Steam / Itch.io / Humble — "No new games" (OK)
No active free games on these platforms in the GamerPower results currently.

## Architecture Reference

- `src/index.js` — Main orchestrator: discover → post to Discord → claim on each platform
- `src/discover.js` — GamerPower API + Epic direct API
- `src/discord.js` — Webhook posting with rich embeds
- `src/state.js` — Dedup via seen.json
- `src/email.js` — Gmail IMAP polling for 2FA codes + SMTP for game code emails
- `src/claim/epic.js` — Playwright Epic claim (always fails due to CAPTCHA)
- `src/claim/epic-checkout.js` — Playwright checkout completion
- `src/claim/amazon.js` — Playwright Amazon Prime Gaming + TOTP
- `src/claim/steam.js` — Playwright Steam + Gmail IMAP for Steam Guard
- `src/claim/gog.js` — Playwright GOG + Gmail IMAP for 2FA
- `src/claim/itchio.js` — Playwright Itch.io (blocked by Cloudflare)
- `src/claim/humble.js` — Playwright Humble Bundle + Gmail IMAP for verification
- `src/checkout-server.js` — HTTP webhook server for Epic checkout
- `src/epic-auto-checkout.js` — CLI wrapper for manual checkout

## VM PM2 Processes
- `free-games` (id 12) — Daily at 10:03am PT, cron in ecosystem.config.js
- `epic-claimer` (id 14) — claabs tool, every 6h, at ~/repos/epic-free-claimer/
- `epic-checkout` (id 16) — Webhook server on port 3100

## Credentials
All in `.env` on VM at `~/repos/freeGames/.env`. Includes:
- Epic, Steam, Amazon (with TOTP), GOG, Itch.io, Humble Bundle
- Gmail IMAP + SMTP for email code polling and game code emails
- Discord webhooks for #free-games and #free-game-claims

## Suggested Approach
1. Fix GOG 2FA — debug the email sender/pattern, test IMAP query
2. Skip Playwright Epic claim in index.js (epic-claimer handles it)
3. Research Epic purchase API for completing checkout without Playwright
4. Run `npm run build` equivalent — this is plain JS, just verify `node src/index.js` works
5. Test on VM after deploying
