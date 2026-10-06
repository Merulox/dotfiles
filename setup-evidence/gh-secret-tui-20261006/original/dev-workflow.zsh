# Loaded by the dev-workflow Home Manager module.
# Keep wrappers transparent: `dev` remains the source of command behavior.

# Credentials are injected per command through Agent Vault/protected files, not
# inherited by every project shell or agent process.
unset OPENROUTER_API_KEY SLACK_BOT_TOKEN

# Standalone Home Manager activation exposes packages here before a full NixOS
# switch updates /etc/profiles/per-user.
typeset -U path PATH
path=("$HOME/.local/bin" "$HOME/.local/state/nix/profiles/home-manager/home-path/bin" $path)
export PATH

alias dv='dev'
alias da='dev attention'
alias dh='dev handoff'
alias dr='dev review'
alias dres='dev resume'
alias ds='dev sync'

# Change to a configured project without evaluating command output as shell code.
dproj() {
  if (( $# != 1 )); then
    print -u2 'usage: dproj PROJECT'
    return 2
  fi

  local project_path
  project_path="$(command dev path "$1")" || return
  builtin cd -- "$project_path"
}

# Long names remain discoverable and pass every argument through unchanged.
dev-attention() {
  command dev attention "$@"
}

dev-handoff() {
  command dev handoff "$@"
}

dev-review() {
  command dev review "$@"
}

dev-resume() {
  command dev resume "$@"
}

dev-sync() {
  command dev sync "$@"
}
