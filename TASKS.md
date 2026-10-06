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

### TASK-20261006-gh-secret-tui — Make bare `gh secret` an interactive TUI
- State: completed
- Owner: Codex
- Next: use `gh secret`; press `s` to change scope and `a` to change the consuming GitHub application.
- Acceptance: interactive bare `gh secret` opens the Textual manager; existing subcommands pass through unchanged; values reach `gh` only over stdin; isolated rollback restores original dispatch.
- Evidence: 13 focused tests and the complete 106-test suite passed; live pseudo-terminal smoke found the `GitHub Secrets` screen and exited 0; `setup-evidence/gh-secret-tui-20261006/VERIFICATION.txt`.
