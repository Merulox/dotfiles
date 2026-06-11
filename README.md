# dotfiles

NixOS (flake-based) config for a terminal-heavy i3 setup. i7-10700KF / RTX 2070 SUPER, 2560×1440 144Hz.

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
nixos/          flake.nix, configuration.nix, home.nix, unstable channel
.config/        alacritty, i3, xmonad, hyprland, ncmpcpp, mpv, qutebrowser
i3blocks/       status bar
scripts/        utilities
```

`sudo nixos-rebuild switch` to apply. Aliased as `update`.
