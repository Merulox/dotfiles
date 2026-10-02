# Secrets operations

## Current runtime

`~/.secrets` and the local Agent Vault are the centralized runtime today.
Existing applications may still read files from `~/.secrets`; Agent Vault reduces
accidental exposure for integrations already routed through its local proxy. It is
not a hard isolation boundary for processes with full access to this host.

- Keep `~/.secrets` and `~/.local/share/agent-vault/data` at mode `0700`.
- Keep secret, token, credential, and environment files at mode `0600`.
- Read the Slack bot token from `SLACK_BOT_TOKEN`, `SLACK_BOT_TOKEN_FILE`, or
  `~/.secrets/slack-bot-token.txt`. Never echo it.
- Pass credentials through environment variables, protected files, or the local
  Agent Vault proxy. Never paste values into prompts or command arguments.
- Never commit secret values, decrypted files, credential-bearing diffs, or vault
  data. Never include them in logs, reports, screenshots, test fixtures, or error
  messages.
- Audit names, permissions, and presence only; do not print file contents.

Create and repair private storage without reading values:

```sh
install -d -m 0700 "$HOME/.secrets" "$HOME/.local/share/agent-vault/data"
find "$HOME/.secrets" -type d -exec chmod 0700 {} +
find "$HOME/.secrets" -type f -exec chmod 0600 {} +
find "$HOME/.local/share/agent-vault/data" -type d -exec chmod 0700 {} +
find "$HOME/.local/share/agent-vault/data" -type f -exec chmod 0600 {} +
```

Use `dev secrets audit` for a non-content permission check of the Slack delivery credential. Use the `find` checks above for the complete file-backed secret store.

## Backups and recovery checks

Two declarative daily paths cover the file-backed store:

- NixOS `services.restic.backups.r2` backs up `~/.secrets` with the repository password and R2 credentials held in protected files. Its retention is 7 daily, 4 weekly, and 6 monthly snapshots.
- The Home Manager `backup-secrets-proton.timer` creates a mode-private temporary archive and uploads both a timestamped copy and `latest-secrets.tar.gz` to `/my-files/recovery/secrets` through the pinned official Proton Drive CLI. The temporary archive is removed on exit.

Check metadata and status without reading secret values:

```sh
systemctl status restic-backups-r2.timer --no-pager
systemctl --user status backup-secrets-proton.timer --no-pager
systemctl --user show backup-secrets-proton.service -p ExecMainStatus -p Result
```

Treat an enabled timer as scheduling evidence, not a restore receipt. Periodically select a Restic snapshot or download a timestamped Proton archive into a mode-`0700` temporary directory, list expected file names only, verify the archive, and delete the restored copy. Restore into `~/.secrets` only after checking the selected backup date and resetting directories to `0700` and files to `0600`.

## Future sops/age migration

A sops/age migration is planned, not active. No public age recipient is currently
configured, so this repository intentionally has no `.sops.yaml` and must not
claim encrypted-secret management is operational.

Before migration:

1. Create an age identity outside Git and record a recoverable public recipient.
2. Back up and restore-test the identity through the existing recovery process.
3. Add `.sops.yaml` with public recipients only, encrypt a disposable canary, and
   verify decryption after a clean checkout.
4. Migrate one consumer at a time while retaining a tested rollback path.
5. Remove old plaintext material only after every consumer and recovery path has
   been verified.

Public recipients and encrypted payloads may eventually be versioned; private age
identities and decrypted values never belong in Git.
