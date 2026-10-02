# Context

## Objective

Deliver the outcome and authority boundaries in `PROJECT.md`.

## Current state

- Working behavior: the `dev` CLI is live through Home Manager, routes 17 projects, delegates OMP lifecycle to Realm, launches Codex/Claude, persists append-only state, and queues Slack reports offline.
- Active constraint: Slack channel creation/delivery is dormant until a protected bot token is installed.
- Known blocker: Navidrome Last.fm remains disabled until the previously embedded shared secret is rotated; the declarative source and protected environment-file replacement are ready.

## Interfaces

- Inputs: `nixos/workflow/config/projects.toml`, Realm `portfolio.toml`, repository contracts, native agent transcripts, and protected credential files.
- Outputs: terminal commands, repository state files, the private local event/outbox ledgers, and optional Slack projections.
- External dependencies: NixOS/Home Manager, Realm/session-workspace, tmux, Git, OMP, Codex, Claude, Agent Vault, and Slack when provisioned.

## Verification

Run `dev doctor`, `python3 -m unittest discover -s tests -v`, and `nix flake check --no-build "path:$PWD/nixos"`.
