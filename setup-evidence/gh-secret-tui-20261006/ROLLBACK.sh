#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd -- "$SCRIPT_DIR/../.." && pwd)"
ACTIVATE=0

while (($#)); do
  case "$1" in
    --root)
      ROOT="$(cd -- "$2" && pwd)"
      shift 2
      ;;
    --activate)
      ACTIVATE=1
      shift
      ;;
    *)
      printf 'usage: %s [--root REPOSITORY] [--activate]\n' "$0" >&2
      exit 2
      ;;
  esac
done

cp -- "$SCRIPT_DIR/original/dev-workflow.nix" "$ROOT/nixos/home/dev-workflow.nix"
cp -- "$SCRIPT_DIR/original/dev-workflow.zsh" "$ROOT/nixos/workflow/shell/dev-workflow.zsh"
rm -f -- "$ROOT/nixos/workflow/bin/gh-secret-tui" "$ROOT/tests/test_gh_secret_tui.py"

expected_nix="$(sha256sum "$SCRIPT_DIR/original/dev-workflow.nix" | awk '{print $1}')"
expected_zsh="$(sha256sum "$SCRIPT_DIR/original/dev-workflow.zsh" | awk '{print $1}')"
actual_nix="$(sha256sum "$ROOT/nixos/home/dev-workflow.nix" | awk '{print $1}')"
actual_zsh="$(sha256sum "$ROOT/nixos/workflow/shell/dev-workflow.zsh" | awk '{print $1}')"
[[ "$actual_nix" == "$expected_nix" ]]
[[ "$actual_zsh" == "$expected_zsh" ]]

if ((ACTIVATE)); then
  flake="git+file://$ROOT?dir=nixos#nixosConfigurations.navi.config.home-manager.users.merulox.home.activationPackage"
  activation="$(nix build --no-link --print-out-paths "$flake")"
  "$activation/activate"
fi

printf 'ROLLBACK restored bare gh secret help behavior; root=%s; activated=%s\n' "$ROOT" "$ACTIVATE"
