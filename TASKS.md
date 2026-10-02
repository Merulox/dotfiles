# Tasks

Task records are append-only. Each task has one outcome, owner, state, next action, and acceptance check.

<!--
### TASK-ID — short outcome
- State: open | active | blocked | completed
- Owner:
- Next:
- Acceptance:
- Evidence:
-->

### TASK-0f2254b1e70b — Rotate the Navidrome Last.fm shared secret
- State: blocked
- Owner: operator
- Next: rotate the shared secret in Last.fm, update `~/.secrets/navidrome-lastfm-secret` and `~/.secrets/navidrome.env`, run `update`, then set `LastFM.enabled = true`.
- Acceptance: `systemctl status navidrome` shows the rebuilt service active and Last.fm scrobbling succeeds without a secret in the Nix store.
- Evidence: current declarative configuration sets `LastFM.enabled = false` and reads the protected systemd `EnvironmentFile`.
