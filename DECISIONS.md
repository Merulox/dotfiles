# Decisions

Decision records are append-only. Supersede a decision explicitly instead of rewriting history.

<!--
## YYYY-MM-DD — DECISION-ID
- Status: proposed | accepted | rejected | superseded
- Decision:
- Context:
- Evidence:
- Consequences:
- Supersedes:
-->

## decision e9fec7c8d41c
- timestamp: `2026-10-02T08:49:59+00:00`
- status: accepted
- text: Keep Realm as portfolio authority; use dev only for routing, repository context, agent lifecycle delegation, and Slack projection.

## 2026-10-06 — DECISION-gh-secret-interactive-dispatch
- Status: accepted
- Decision: intercept only interactive `gh secret` and explicit `gh secret tui` in the workflow zsh layer; keep `gh secret list`, `set`, `delete`, `--help`, non-interactive use, and all other `gh` commands on the official CLI.
- Context: GitHub CLI exposes complete secret operations but bare `gh secret` only prints help. A terminal manager improves discovery without replacing the authenticated/encrypted `gh` backend.
- Evidence: `tests/test_gh_secret_tui.py`, live Home Manager activation, and the authenticated metadata-only list check in `setup-evidence/gh-secret-tui-20261006/VERIFICATION.txt`.
- Consequences: secret values remain write-only and travel over subprocess stdin; repository, environment, organization, and user scopes are selectable; organization/user selected-repository policies are reloaded before updates.
- Supersedes: none.
