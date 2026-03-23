# navi_hook.sh — source this in your .zshrc or .bashrc
# Usage: source ~/.config/navi/navi_hook.sh

NAVI_FIFO="/tmp/navi.pipe"

# ── JSON string escaper (python3, but only once per command not per char) ─────
_navi_json_str() {
  printf '%s' "$1" | python3 -c '
import json,sys
print(json.dumps(sys.stdin.read()))
'
}

_navi_send() {
  local cmd="$1" exit_code="$2" cwd="$3" duration="$4"
  [ -z "$cmd" ] && return
  [ ! -p "$NAVI_FIFO" ] && return
  local payload
  payload="{\"cmd\":$(_navi_json_str "$cmd"),\"exit\":$exit_code,\"cwd\":$(_navi_json_str "$cwd"),\"duration\":$duration,\"output\":\"\"}"
  echo "$payload" > "$NAVI_FIFO" &
  disown 2>/dev/null || true
}

# ── ZSH ───────────────────────────────────────────────────────────────────────
if [ -n "$ZSH_VERSION" ]; then

  _navi_last_cmd=""
  _navi_cmd_start=0

  _navi_preexec() {
    _navi_last_cmd="$1"
    _navi_cmd_start=$(date +%s%3N)
  }

  _navi_precmd() {
    local exit_code=$?
    local cmd="$_navi_last_cmd"
    _navi_last_cmd=""
    [ -z "$cmd" ] && return
    local duration=$(( $(date +%s%3N) - _navi_cmd_start ))
    _navi_send "$cmd" "$exit_code" "$PWD" "$duration"
  }

  autoload -Uz add-zsh-hook
  add-zsh-hook preexec _navi_preexec
  add-zsh-hook precmd  _navi_precmd

# ── BASH ──────────────────────────────────────────────────────────────────────
elif [ -n "$BASH_VERSION" ]; then

  _navi_last_exit=0
  _navi_cmd_start=0
  _navi_in_prompt=0

  _navi_preexec_trap() {
    [ "$_navi_in_prompt" = "1" ] && return
    _navi_cmd_start=$(date +%s%3N 2>/dev/null || echo 0)
  }

  _navi_precmd() {
    _navi_last_exit=$?
    _navi_in_prompt=1
    local cmd
    cmd=$(HISTTIMEFORMAT='' history 1 | sed 's/^ *[0-9]* *//')
    local duration=$(( $(date +%s%3N 2>/dev/null || echo 0) - _navi_cmd_start ))
    _navi_send "$cmd" "$_navi_last_exit" "$PWD" "$duration"
    _navi_in_prompt=0
  }

  trap '_navi_preexec_trap' DEBUG
  PROMPT_COMMAND="${PROMPT_COMMAND:+$PROMPT_COMMAND;}_navi_precmd"

fi

# ── manual message ────────────────────────────────────────────────────────────
navi_say() {
  [ -z "$1" ] && return
  [ ! -p "$NAVI_FIFO" ] && echo "navi: pipe not found — is the daemon running?" && return
  local payload
  payload="{\"cmd\":\"<direct>\",\"exit\":0,\"cwd\":$(_navi_json_str "$PWD"),\"duration\":0,\"output\":$(_navi_json_str "$1"),\"direct\":true}"
  echo "$payload" > "$NAVI_FIFO"
}
