#!/usr/bin/env bash
# start_navi.sh — launch a tmux session with navi in a split pane

SESSION="${1:-navi}"
NAVI_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NAVI_PY="$NAVI_DIR/navi.py"
MODEL="${NAVI_MODEL:-mistral}"
DISPLAY="${DISPLAY:-:0}"

# ── check dependencies ────────────────────────────────────────────────────────
check_dep() {
  command -v "$1" &>/dev/null || { echo "missing: $1"; exit 1; }
}
check_dep tmux
check_dep python3

# ── ensure model is pulled ────────────────────────────────────────────────────
if ! ollama list 2>/dev/null | grep -q "^${MODEL}"; then
  echo "pulling model: $MODEL"
  ollama pull "$MODEL"
fi

# ── create/verify FIFO ───────────────────────────────────────────────────────
if [ -e /tmp/navi.pipe ] && [ ! -p /tmp/navi.pipe ]; then
  rm -f /tmp/navi.pipe
fi
[ -p /tmp/navi.pipe ] || mkfifo /tmp/navi.pipe

# ── attach if session exists ──────────────────────────────────────────────────
if tmux has-session -t "$SESSION" 2>/dev/null; then
  echo "attaching to existing session '$SESSION'"
  tmux attach -t "$SESSION"
  exit 0
fi

# ── create session and split ──────────────────────────────────────────────────
tmux new-session -d -s "$SESSION"
sleep 0.3

# split bottom 20% off — now there are two panes in the session
tmux split-window -v -p 20 -t "$SESSION"
sleep 0.2

# pane 0 = top (main shell), pane 1 = bottom (navi)
# use %0 %1 syntax which is stable regardless of window numbering
MAIN_PANE="%0"
NAVI_PANE="%1"

# style navi pane
tmux select-pane -t "$SESSION" -P 'bg=colour233,fg=colour147' 2>/dev/null || true
tmux send-keys -t "$NAVI_PANE" "clear" Enter
sleep 0.1

# start daemon
tmux send-keys -t "$NAVI_PANE" \
  "export DISPLAY='$DISPLAY'; NAVI_LOG=/tmp/navi.log NAVI_MODEL='$MODEL' python3 '$NAVI_PY'" Enter

# go back to main pane and source hook
tmux select-pane -t "$MAIN_PANE"
sleep 0.2
tmux send-keys -t "$MAIN_PANE" \
  "source '$NAVI_DIR/navi_hook.sh' && echo 'navi is watching'" Enter

tmux attach -t "$SESSION"
