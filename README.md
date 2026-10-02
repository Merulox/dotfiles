# dotfiles

NixOS (flake-based) config for a terminal-heavy i3 setup. i7-10700KF / RTX 2070 SUPER, 2560×1440 144Hz.

## Development workflow

`dev` is the terminal entry point for project navigation, agent launch/recovery, handoffs, review, sync, and Slack reporting. Start with [SYSTEM.md](SYSTEM.md), then use the [daily workflow](docs/DAILY_WORKFLOW.md) and [Slack operations](docs/SLACK.md) guides.

## Stack

| | |
|---|---|
| **WM** | i3 (primary) — xmonad + hyprland also tracked |
| **Terminal** | Alacritty — Terminess Nerd Font Mono 10pt, antialiasing off |
| **Shell** | zsh + oh-my-zsh |
| **Editor** | neovim (default), doom emacs |
| **Music** | mpd + ncmpcpp, scrobbled to last.fm + listenbrainz |
| **Compositor** | picom — blur, shadows, per-window opacity |
| **Theme switching** | darkman — GTK + Alacritty colors swap automatically at sunset |
| **Other** | qutebrowser, mpv, hyprland (experimental), navi |

## Layout

```
nixos/          canonical navi flake, machine config, Home Manager, workflow payload
bin/             terminal entry points (symlinked into nixos/workflow)
config/          machine-local routing overlay defaults
docs/            daily workflow and Slack operations
templates/       project context/task/decision/recovery contract
.config/         alacritty, i3, xmonad, hyprland, ncmpcpp, mpv, qutebrowser
i3blocks/        status bar
scripts/         utilities
```

Apply with `sudo nixos-rebuild switch --flake "$HOME/git/dotfiles/nixos#navi"` (aliased as `update`).
