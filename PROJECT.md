# Navi development workstation

## Objective

Make the complete terminal-first development environment reproducible from this private repository while keeping project state, agent sessions, credentials, and operator reporting recoverable after interruption.

## Success contract

- Observable result: a clean checkout can evaluate and build `nixos#navi`, activate the Home Manager workflow, and expose one `dev` command for every registered project.
- Verification: `nix flake check --no-build "path:$PWD/nixos"`, the CLI unit suite, `dev doctor`, and an isolated rollback all pass.
- Stop condition: source, tests, operating docs, and rollback evidence are committed and pushed; only external credential provisioning or privileged machine activation may remain.

## Boundaries

- In scope: NixOS/Home Manager, shell and CLI tooling, project contracts, OMP/Codex/Claude launch and recovery, local event/outbox state, Slack projection, and secret references.
- Out of scope: a second portfolio database, replacing native agent transcripts, storing plaintext credentials in Git, or adding another web dashboard.

## Authority

Realm's `/home/merulox/projects/realm/portfolio.toml` governs portfolio lifecycle and thesis. This file governs this repository's implementation objective only.
