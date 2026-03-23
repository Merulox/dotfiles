#!/usr/bin/env bash
# Links config files into ~/git/dotfiles using hardlinks (same as existing setup)
# Run this whenever you add new config files you want tracked

DOTFILES="$HOME/git/dotfiles"

link() {
  local src="$1"
  local dst="$DOTFILES/$2"
  mkdir -p "$(dirname "$dst")"
  if [ -f "$src" ]; then
    ln -f "$src" "$dst" && echo "linked: $2"
  else
    echo "skip (missing): $src"
  fi
}

# Alacritty
link ~/.config/alacritty/alacritty.toml .config/alacritty/alacritty.toml

# Hyprland
link ~/.config/hypr/hyprland.conf .config/hypr/hyprland.conf

# htop
link ~/.config/htop/htoprc .config/htop/htoprc

# GTK
link ~/.config/gtk-3.0/settings.ini .config/gtk-3.0/settings.ini
link ~/.config/gtk-3.0/gtk.css .config/gtk-3.0/gtk.css
link ~/.config/gtk-2.0/gtkfilechooser.ini .config/gtk-2.0/gtkfilechooser.ini

# yams (last.fm scrobbler config only, not log/pid)
link ~/.config/yams/yams.yml .config/yams/yams.yml

# navi daemon (not memory.json or navi.log)
link ~/.config/navi/navi.py .config/navi/navi.py
link ~/.config/navi/navi_hook.sh .config/navi/navi_hook.sh
link ~/.config/navi/start_navi.sh .config/navi/start_navi.sh
link ~/.config/navi/README.md .config/navi/README.md

# qutebrowser
link ~/.config/qutebrowser/autoconfig.yml .config/qutebrowser/autoconfig.yml
link ~/.config/qutebrowser/quickmarks .config/qutebrowser/quickmarks

# autokey
link ~/.config/autokey/autokey.json .config/autokey/autokey.json

# scripts
mkdir -p "$DOTFILES/scripts"
for f in ~/scripts/*; do
  [ -f "$f" ] && ln -f "$f" "$DOTFILES/scripts/$(basename "$f")" && echo "linked: scripts/$(basename "$f")"
done

echo ""
echo "Done. Run 'cd ~/git/dotfiles && git add -A && git status' to review."
