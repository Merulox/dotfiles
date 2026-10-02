#!/usr/bin/env bash
set -euo pipefail

# Compatibility entry point. The old implementation hard-linked mutable files
# and swept every file in ~/scripts into Git; that made rollback and review
# unreliable. The canonical deployment is now the tracked Nix flake.

repo="${DOTFILES_REPO:-$HOME/git/dotfiles}"
flake="path:$repo/nixos"
host="${NIXOS_HOST:-navi}"

usage() {
  printf 'usage: %s <check|status|test|apply>\n' "${0##*/}" >&2
  exit 2
}

case "${1:-}" in
  check)
    exec nix flake check --no-build "$flake"
    ;;
  status)
    git -C "$repo" status --short --branch
    printf '\nCanonical flake: %s#%s\n' "$repo/nixos" "$host"
    printf 'Live source:     /etc/nixos (compatibility only)\n'
    ;;
  test)
    exec sudo nixos-rebuild test --flake "$repo/nixos#$host"
    ;;
  apply)
    exec sudo nixos-rebuild switch --flake "$repo/nixos#$host"
    ;;
  *)
    usage
    ;;
esac
