# Daily development workflow

Run `dev` from any directory. Replace `PROJECT` with the project ID from `dev projects`; do not infer an ID from a directory name.

## Start of day

```bash
dev doctor
dev projects
dev status
dev attention
```

Choose the project and review the durable context before launching an agent:

```bash
dev review PROJECT
dev context PROJECT
```

`review` is the compact operator view. `context` emits the assembled repository contract for an agent or a deeper inspection. Realm remains the source for portfolio lifecycle and thesis; these commands do not maintain a second portfolio registry.

## Start work

`start` is safe to inspect by default: without `--exec` it prints the exact command and does not launch anything.

```bash
# Inspect, then launch an OMP session through realm-session.
dev start PROJECT --agent omp --name WORK-NAME
dev start PROJECT --agent omp --name WORK-NAME --exec

# Other supported agents.
dev start PROJECT --agent codex
dev start PROJECT --agent codex --exec
dev start PROJECT --agent claude
dev start PROJECT --agent claude --exec

# A project tmux shell.
dev start PROJECT --agent shell --name WORK-NAME
dev start PROJECT --agent shell --name WORK-NAME --exec
```

OMP launch delegates to the PATH-resolved `realm-session agent start ... --cwd ... --claim ...`. Claims remain owned by `session-workspace`; `dev` does not implement a parallel claim registry. Codex and Claude launch in the resolved project directory and retain their native transcript systems.

Record work in the repository contract, not in Slack:

```bash
dev task PROJECT "Implement the bounded change"
dev decision PROJECT "Use the repository-native adapter" --status accepted
dev status PROJECT
```

## Handoff, report, and review

A handoff must state who receives it, what changed, and the next executable action:

```bash
dev handoff PROJECT \
  --to ROLE \
  --summary "Implemented and verified the adapter" \
  --next "Review the diff and run the integration check"
```

Include a blocker when the receiver cannot continue immediately:

```bash
dev handoff PROJECT \
  --to ROLE \
  --summary "Prepared the migration" \
  --next "Inject the service credential, then rerun the canary" \
  --blocker "Credential is not present"
```

Publish concise operational reports with one of the four supported labels:

```bash
dev report PROJECT --type progress --message "Adapter implemented" --next "Run review"
dev report PROJECT --type blocker --message "Credential missing" --next "Inject token"
dev report PROJECT --type decision --message "Kept Realm as authority"
dev report PROJECT --type handoff --message "Ready for reviewer" --next "Inspect task-owned diff"
```

Every report first enters the local event ledger and Slack outbox. Network delivery is separate; see [SLACK.md](SLACK.md).

Before stopping:

```bash
dev sync PROJECT
dev review PROJECT
git -C "$(dev path PROJECT)" status --short
```

`dev sync PROJECT` deterministically replaces only that project's generated `RECENT_CHANGES.md` using Git log/status. It preserves `CONTEXT.md`, `TASKS.md`, `DECISIONS.md`, and `RECOVERY.md`. Use `dev sync` with no project to sync every configured project.

## Resume normal work

Always inspect first:

```bash
dev resume PROJECT
```

For a matching running OMP session, this prints its exact attach command. For a matching interrupted OMP session, it prints the guarded `dev` command that reclaims through `session-workspace` before asking Realm to resume:

```text
dev resume PROJECT --exec
```

After checking the displayed session and claim, run that emitted command. Do not invoke a bare `realm-session agent start --resume` command, because it bypasses `dev`'s serialized claim guard.

If no matching OMP record exists, `resume` shows repository recovery/context and does not invent a session ID or a new source of authority.

## Recover after a crash

First recover the OMP lifecycle inventory, then resolve one project:

```bash
dev recover
dev resume PROJECT
```

`dev recover` delegates to the PATH-resolved lifecycle command:

```bash
realm-session agent recover
```

Then follow the agent-specific path:

### OMP

```bash
dev resume PROJECT
dev resume PROJECT --exec
```

The session JSONL and Realm session registry determine the recovery command. Confirm the former process is gone; never run two writers against one OMP session JSONL.

### Codex

```bash
cd "$(dev path PROJECT)"
codex resume
```

Select the native Codex transcript for that project. Use `dev review PROJECT` to reconcile it with the repository contract. Do not copy the transcript into workflow state.

### Claude

```bash
cd "$(dev path PROJECT)"
claude --continue
```

Claude resumes its native project conversation. If the last conversation is not the intended work, use Claude's native session picker rather than fabricating workflow history. Reconcile the result with `dev review PROJECT`.

For all agents, the transcript restores conversational detail; the repository contract restores durable cross-agent state. `RECOVERY.md` must name any project-specific restart or verification steps. Slack is never the recovery authority.

## Add a project contract

Initialize a repository explicitly:

```bash
dev init /absolute/path/to/repository --id PROJECT
```

This creates the required project contract files and, for a new project, root `AGENTS.md` and `PROJECT.md`. It appends the route to the writable `$DEV_WORKFLOW_CONFIG_LOCAL` overlay (default: `projects.local.toml` beside the base config), never to the Home Manager/store-managed base. The overlay is merged recursively over `$DEV_WORKFLOW_CONFIG`. Routing belongs in these TOML files; lifecycle, thesis, and portfolio relationships stay in Realm.

`init` deliberately leaves `CONTEXT.md` and `RECOVERY.md` as templates. Replace their prompts with factual working behavior, constraints, restart steps, and verification evidence. Until both are populated, `dev status PROJECT` reports them as `template-only` and the project remains in `needs attention`.

## Apply this dotfiles configuration

The repository's `nixos/` directory is the canonical flake. It contains the `navi` hardware configuration, the Home Manager module, and the complete deployable `nixos/workflow/` subtree. Root `bin/`, `config/`, `shell/`, and `templates/` paths are convenience symlinks into that canonical subtree.

Evaluate first, then apply host `navi`:

```bash
nix flake check --no-build "path:$HOME/git/dotfiles/nixos"
sudo nixos-rebuild test --flake "$HOME/git/dotfiles/nixos#navi"
sudo nixos-rebuild switch --flake "$HOME/git/dotfiles/nixos#navi"
```

The Home Manager module exposes `dev` at `~/.local/bin/dev`, installs the immutable base routing config and project templates, and loads shell integration. Local routes created by `dev init` remain in the writable `projects.local.toml` overlay. Open a new shell after rebuilding, then inspect the installation:

```bash
command -v dev
dev doctor
dev projects
```

Environment overrides for isolated or temporary runs are:

```bash
export DEV_WORKFLOW_CONFIG=/path/to/projects.toml
export DEV_WORKFLOW_CONFIG_LOCAL=/path/to/projects.local.toml
export DEV_WORKFLOW_STATE=/path/to/runtime-state
```
