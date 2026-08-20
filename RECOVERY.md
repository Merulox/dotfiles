# Navi recovery guide

This file lives at the root of the dotfiles repository because it must be reachable before the NixOS configuration, Proton archive, or Restic repository has been restored.

## Recovery order

1. Clone the private dotfiles repository and read this file.
2. Recover `~/.secrets` from Proton Drive.
3. Use the recovered R2 credentials and Restic password to inspect and restore the R2 repository.
4. Restore `/etc/nixos`, rebuild the machine, then restore selected home data.
5. Verify the Boréal database before restarting any writer.

Never restore directly over a running system without first restoring into a staging directory and inspecting the result.

## What is backed up

| Data | Destination | Schedule | Unit |
|---|---|---:|---|
| `~/.secrets` bootstrap archive | Proton Drive `/my-files/recovery/secrets` | daily | `backup-secrets-proton.timer` (user) |
| `.secrets`, `projects`, KeePassXC config, rclone config | Cloudflare R2 Restic repository | daily | `restic-backups-r2.timer` (system) |
| `/etc/nixos` and most of `/home/merulox` | Same Cloudflare R2 Restic repository | daily | `backup-r2.timer` (user) |
| Dotfiles Git repository | configured Git remote | daily, when dirty | `backup-dotfiles.timer` (user) |
| `projects/boreal/leads/crm.db` consistent snapshots | `projects/boreal/leads/_db-backups` | hourly, newest 48 local | `boreal-db-backup.timer` (user) |

The hourly Boréal snapshots are inside the home/project backup scope, so successful R2 runs carry them off-machine.

## 1. Recover secrets from Proton Drive

Install Proton's official Drive CLI for Linux, then authenticate interactively:

```bash
proton-drive auth login
```

Confirm the newest timestamped archive exists:

```bash
proton-drive filesystem list /my-files/recovery/secrets --json \
  | jq -r 'sort_by(.creationTime) | .[] | [.creationTime, .name.value] | @tsv'
```

Download the stable alias into a staging directory:

```bash
mkdir -p "$HOME/recovery/proton"
chmod 700 "$HOME/recovery/proton"
proton-drive filesystem download \
  /my-files/recovery/secrets/latest-secrets.tar.gz \
  "$HOME/recovery/proton"
tar -tzf "$HOME/recovery/proton/latest-secrets.tar.gz"
```

If the alias metadata is older than the newest timestamped archive, the secret bytes may simply have been unchanged and Proton skipped replacing the identical alias. When uncertain, download the newest `secrets-YYYYMMDDTHHMMSSZ.tar.gz` explicitly.

Extract into staging, inspect, then install:

```bash
mkdir -p "$HOME/recovery/secrets"
tar -xzf "$HOME/recovery/proton/latest-secrets.tar.gz" \
  -C "$HOME/recovery/secrets"
mkdir -p "$HOME/.secrets"
chmod 700 "$HOME/.secrets"
cp -a "$HOME/recovery/secrets/.secrets/." "$HOME/.secrets/"
chmod -R go-rwx "$HOME/.secrets"
```

Do not print or paste secret values while diagnosing the restore.

## 2. Inspect and restore Cloudflare R2

Export the credential-file assignments before invoking Restic:

```bash
set -a
source "$HOME/.secrets/r2-credentials"
set +a
export RESTIC_REPOSITORY='s3:https://85fd3bf83c5ee32ce2e3353fa0a58409.r2.cloudflarestorage.com/navi-backup'
export RESTIC_PASSWORD_FILE="$HOME/.secrets/restic-password"
restic snapshots
```

There are multiple snapshot path groups in the same repository. Select a snapshot ID by its timestamp and `Paths`; do not assume that `latest` refers to the full-home snapshot.

Restore the selected snapshot into staging:

```bash
mkdir -p "$HOME/recovery/r2"
restic restore SNAPSHOT_ID --target "$HOME/recovery/r2"
```

Absolute source paths appear under the staging root, for example:

```text
~/recovery/r2/etc/nixos/
~/recovery/r2/home/merulox/projects/
```

Inspect those trees before copying anything onto the live filesystem.

## 3. Restore NixOS

Stage the recovered configuration, compare it with any installer-generated configuration, then activate it:

```bash
sudo mkdir -p /etc/nixos
sudo cp -a "$HOME/recovery/r2/etc/nixos/." /etc/nixos/
sudo nixos-rebuild switch --flake /etc/nixos#navi
```

If `/etc/nixos` was not present in the chosen R2 snapshot, use the `nixos/` copy from this dotfiles repository as the bootstrap configuration, then reconcile it with the newer R2 copy when available.

Restore home data selectively. Preview every copy first:

```bash
rsync -an "$HOME/recovery/r2/home/merulox/projects/" "$HOME/projects/"
# Remove -n only after the preview is correct.
```

Do not replace live session JSONL files while any OMP process is running.

## 4. Restore the Boréal database

Stop every process that can write `crm.db` before replacement. At minimum, stop the campaign/follow-up timers and the SMS inbox if they are enabled:

```bash
systemctl --user stop boreal-campaign.timer boreal-followup.timer
sudo systemctl stop sms-inbox.service 2>/dev/null || true
```

Choose the newest recovered `crm-*.db`, then verify it:

```bash
sqlite3 /path/to/crm-YYYYMMDD-HHMMSS.db 'PRAGMA integrity_check;'
```

The only acceptable result is `ok`. Preserve the current database before replacing it:

```bash
cp -a "$HOME/projects/boreal/leads/crm.db" \
  "$HOME/projects/boreal/leads/crm.db.pre-restore"
cp -a /path/to/crm-YYYYMMDD-HHMMSS.db \
  "$HOME/projects/boreal/leads/crm.db"
sqlite3 "$HOME/projects/boreal/leads/crm.db" 'PRAGMA integrity_check;'
```

Restart only the units that were enabled before the restore.

## 5. Recover OMP sessions after a crash

The session JSONL is the source of truth. Never run two writers against one session JSONL.

```bash
realm-session agent recover
realm-session agent list
```

Resume only unfinished top-level sessions. Confirm the previous process is gone before running:

```bash
omp --resume SESSION_ID
```

Do not restart sessions whose todo plan is already complete. Child-agent transcripts remain stored beside the top-level session.

## Memory-pressure recovery

Start with evidence:

```bash
free -h
realm-session agent list
tmux list-panes -a -F '#{session_name}\tpid=#{pane_pid}\tcmd=#{pane_current_command}\t#{pane_title}'
```

For each old OMP pane, inspect its last output before killing it:

```bash
tmux capture-pane -p -S -50 -t SESSION_NAME
```

Kill only sessions that are complete, have released their workspace claims, and are no longer needed:

```bash
tmux kill-session -t SESSION_NAME
```

Do not run `tmux-nuke-orphans` blindly: it has no workspace-claim check. Do not drop Linux caches; they are reclaimable. Do not run `swapoff` unless available RAM comfortably exceeds used swap. A high swap number alone is not pressure; check `MemAvailable` and memory PSI.

## Routine health checks

User units need the user bus when run outside the desktop session:

```bash
export XDG_RUNTIME_DIR=/run/user/$(id -u)
export DBUS_SESSION_BUS_ADDRESS="unix:path=$XDG_RUNTIME_DIR/bus"
```

Check timers and last results:

```bash
systemctl list-timers --all restic-backups-r2.timer
systemctl show restic-backups-r2.service \
  --property=Result --property=ExecMainStatus --property=ExecMainExitTimestamp

systemctl --user list-timers --all \
  backup-r2.timer backup-secrets-proton.timer backup-dotfiles.timer \
  boreal-db-backup.timer
systemctl --user show \
  backup-r2.service backup-secrets-proton.service \
  backup-dotfiles.service boreal-db-backup.service \
  --property=Id --property=Result --property=ExecMainStatus \
  --property=ExecMainExitTimestamp
```

Expected completed-oneshot state: `Result=success`, `ExecMainStatus=0`, and usually `ActiveState=inactive`.

Verify remote artifacts, not only local unit state:

```bash
# R2
set -a; source "$HOME/.secrets/r2-credentials"; set +a
export RESTIC_REPOSITORY='s3:https://85fd3bf83c5ee32ce2e3353fa0a58409.r2.cloudflarestorage.com/navi-backup'
export RESTIC_PASSWORD_FILE="$HOME/.secrets/restic-password"
restic snapshots --latest 5

# Proton
proton-drive filesystem list /my-files/recovery/secrets --json \
  | jq -r 'sort_by(.creationTime) | .[-1] | [.creationTime, .name.value] | @tsv'

# Dotfiles
git -C "$HOME/git/dotfiles" status --short --branch
git -C "$HOME/git/dotfiles" rev-list --left-right --count main...origin/main

# Latest local Boréal snapshot
sqlite3 /path/to/latest/crm-YYYYMMDD-HHMMSS.db 'PRAGMA integrity_check;'
```

A green timer without a recent remote artifact is not a verified backup. Periodically perform a staged restore; backup creation alone does not prove recoverability.
