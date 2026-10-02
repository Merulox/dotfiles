# Development workstation system

`dev` is the terminal entry point for moving between projects, reading project context, launching agents, handing work off, recovering sessions, and reporting status. It is a routing and workflow layer; it is not a second portfolio system.

## Authority and state

- **Realm remains authoritative** for portfolio identity, lifecycle, thesis, relationships, and the cross-project system model.
- **Each repository remains authoritative for its work state.** `dev` resolves a configured `state_dir` first, then `.agent/`, then the repository root. An external state directory is a fallback only when the repository has no native contract.
- A project contract consists of `CONTEXT.md`, `TASKS.md`, `DECISIONS.md`, `RECOVERY.md`, and `RECENT_CHANGES.md`. New projects also receive root `AGENTS.md` and `PROJECT.md`.
- Agent-native transcripts remain the session record. OMP session JSONL, Codex history, and Claude history are not copied into a new transcript store.
- The generated Realm `MANIFEST.md` is a compatibility projection for existing consumers, not an editable authority.
- The workflow adds no project database. Its local JSON/JSONL files are delivery/cache/runtime state, not portfolio state.

The immutable/base routing config is `$DEV_WORKFLOW_CONFIG` (default `~/.config/dev-workflow/projects.toml`). A writable recursive overlay is `$DEV_WORKFLOW_CONFIG_LOCAL` (default: sibling `projects.local.toml`); overlay values win. These files contain only project paths, optional state adapters, and Slack channel aliases. Runtime files live at `$DEV_WORKFLOW_STATE` (default `~/.local/state/dev-workflow`).

## Component decisions

| Decision | Component | Boundary |
|---|---|---|
| Keep | Realm portfolio/system model | Canonical portfolio authority and dependency model |
| Keep | Commander | Operator UI; it consumes project and Realm state |
| Keep | Aperture | Runtime/system observability; it does not become workflow authority |
| Keep/package | `session-workspace` | Vendored, atomically persisted file/component claims and collision avoidance |
| Keep/package | `realm-session` and `omp-lifecycle` | Vendored Realm launcher for OMP inventory, recovery, and resume lifecycle |
| Keep | OMP, Codex, and Claude native transcripts | Agent-specific conversational continuity |
| Keep | Current Agent Vault | Existing credential boundary; secrets are not copied into config or state |
| Consolidate | Navigation, context assembly, review, handoff, sync, and reporting | One executable: `dev` |
| Replace | Ad hoc project lookup, hand-maintained cross-project indexes, and scattered reporting commands | `dev` plus repository-native contracts |
| Compatibility only | Generated Realm `MANIFEST.md` | Existing readers may consume it; humans and tools do not write authority into it |

Nothing in `dev` replaces Commander, Aperture, Realm, the claim registry, or agent lifecycle semantics. It delegates to them and presents one deterministic terminal surface. The clean-checkout snapshot vendors `realm-session`, `session-workspace`, and the Proton backup client wrapper under `nixos/workflow/bin`; Home Manager installs them in `~/.local/bin` so the workflow does not depend on an untracked `~/scripts` copy.

## Data flow

1. `dev` resolves a project from TOML and reads its repository-native contract.
2. `dev start` previews an exact shell, OMP, Codex, or Claude command; `--exec` launches it. OMP launch resolves the packaged `realm-session`, creates a real workspace claim, and serializes claim/start cleanup.
3. Work updates the project contract and its native transcript. `dev sync [PROJECT]` deterministically regenerates only that project's `RECENT_CHANGES.md` from Git log/status; it preserves the other contract files.
4. `dev handoff` and `dev report` append durable events. Slack delivery is an optional projection from the local outbox.
5. `dev resume` reads recovery context and Realm's session registry. It attaches a matching running OMP session, resumes only an interrupted session through the guarded `dev resume PROJECT --exec` transaction, and never revives terminal records.

Operational procedures: [daily workflow](docs/DAILY_WORKFLOW.md) and [Slack](docs/SLACK.md).

## Rebuild and recover

The canonical host flake is `~/git/dotfiles/nixos#navi`; `/etc/nixos` is a compatibility source, not the deployment authority.

```bash
nix flake check --no-build "path:$HOME/git/dotfiles/nixos"
sudo nixos-rebuild test --flake "$HOME/git/dotfiles/nixos#navi"
sudo nixos-rebuild switch --flake "$HOME/git/dotfiles/nixos#navi"
```

After a crash, run `dev recover`, then `dev resume PROJECT`. OMP recovery delegates to `realm-session`; Codex uses `codex resume` in the project directory; Claude uses `claude --continue`. The repository contract supplies durable cross-agent state when a transcript is missing.

Slack is optional delivery. Reports remain durable in the private local ledger/outbox while offline; `dev slack bootstrap --apply` and `dev slack flush` become live after a protected bot token is installed.
