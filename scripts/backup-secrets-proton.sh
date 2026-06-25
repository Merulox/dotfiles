#!/usr/bin/env bash
set -euo pipefail

umask 077

export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
export DBUS_SESSION_BUS_ADDRESS="${DBUS_SESSION_BUS_ADDRESS:-unix:path=$XDG_RUNTIME_DIR/bus}"
export DISPLAY="${DISPLAY:-:0}"

REMOTE="${1:-proton:/home/recovery/secrets}"
STAMP="$(date -u '+%Y%m%dT%H%M%SZ')"
TMPDIR="$(mktemp -d)"
ARCHIVE="$TMPDIR/secrets-$STAMP.tar.gz"
LOG="${XDG_RUNTIME_DIR:-/tmp}/backup-secrets-proton.log"

notify_failure() {
  local status=$?
  local message="Proton secrets backup failed with exit $status. See $LOG"

  if command -v dunstify >/dev/null 2>&1; then
    dunstify -u critical "Secrets backup failed" "$message" || true
  elif command -v notify-send >/dev/null 2>&1; then
    notify-send -u critical "Secrets backup failed" "$message" || true
  fi

  exit "$status"
}

cleanup() {
  rm -rf "$TMPDIR"
}
trap cleanup EXIT
trap notify_failure ERR

exec > >(tee -a "$LOG") 2>&1

tar -czf "$ARCHIVE" -C "$HOME" .secrets
rclone mkdir "$REMOTE"
rclone copyto "$ARCHIVE" "$REMOTE/secrets-$STAMP.tar.gz"
rclone copyto "$ARCHIVE" "$REMOTE/latest-secrets.tar.gz"

echo "Uploaded $REMOTE/secrets-$STAMP.tar.gz"
echo "Updated $REMOTE/latest-secrets.tar.gz"
