#!/bin/bash
nohup layout_manager anime >/dev/null 2>&1 &
nohup trackma-qt >/dev/null 2>&1 &
nohup dolphin ~/pictures/mpv >/dev/null 2>&1 &
nohup alacritty -e ani-cli >/dev/null 2>&1 &&
exit 1
