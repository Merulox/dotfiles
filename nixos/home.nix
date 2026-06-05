{ config, pkgs, lib, ... }:
  let
  in
{
  home.username = "merulox";
  home.homeDirectory = "/home/merulox";
  home.stateVersion = "24.05";
  home.packages = [ pkgs.atool pkgs.httpie pkgs.inotify-tools pkgs.khal pkgs.vdirsyncer ];

  # imports
  imports = [
    #./emacs.nix
    #/home/merulox/openclaw/flake.nix
  ];


  # home-manager
  programs.home-manager.enable = true;

  # network
  #services.network-manager-applet.enable = true;

  #font config
  #fonts.fontconfig.enable = true;

  # fish
   programs.fish = {
    enable = false; # DISABLED
    interactiveShellInit = ''
      set fish_greeting # Disable greeting
      fish_config theme choose "Old School"
      fish_config prompt choose "terlar"
      set fish_prompt_pwd_dir_length 0
    '';
      plugins = [
       { name = "fzf-fish"; src = pkgs.fishPlugins.fzf.src; }
       { name = "done"; src = pkgs.fishPlugins.done.src; }
       { name = "pure"; src = pkgs.fishPlugins.pure.src; }
      #{ name = "tide"; src = pkgs.fishPlugins.tide.src; }
      #{ name = "hydro"; src = pkgs.fishPlugins.hydro.src; }
         
    ];
   };
   # ZSH	
  programs.zsh = {
  enable = true;
  autosuggestion.enable = true;
  syntaxHighlighting.enable = true;
  shellAliases = {
    ghosttrack = "cd ~/projects/GhostTrack && .venv/bin/python3 GhostTR.py";
  };
  oh-my-zsh = {
    enable = true;
    theme = "dst";
    plugins = [ "git" "z" "sudo" ];
  };
  #plugins = [
  #  {
  #    name = "pure";
  #    src = pkgs.fetchFromGitHub {
  #      owner = "sindresorhus";
  #      repo = "pure";
  #      rev = "v1.23.0";
  #      sha256 = "sha256-BmQO4xqd/3QnpLUitD2obVxL0UulpboT8jGNEh4ri8k=";
  #    };
  #  }
  #];
  initContent = ''
  # ── Always inside tmux ───────────────────────────────────────────────────────
  # Each new terminal gets its own independent tmux session.
  # To attach to an existing session: Ctrl+\ (session picker)
  if [[ -z "$TMUX" && -z "$SSH_CONNECTION" && -z "$VSCODE_INJECTION" ]]; then
    exec tmux new-session
  fi

  # Free Ctrl+\ from SIGQUIT so zsh bindkey can use it as the session picker
  stty quit undef

  # navi
  source ~/.config/navi/navi_hook.sh 2>/dev/null
    
  # ctrl+arrow word skip
  bindkey "^[[1;5C" forward-word
  bindkey "^[[1;5D" backward-word

  # Better Ctrl+L - clears screen but keeps scrollback
  clear-screen-scrollback() {
  echoti cup 0 0
  printf '%*s' "$(( LINES * COLUMNS ))" ""
  echoti cup 0 0
  zle clear-screen
  }
  zle -N clear-screen-scrollback
  bindkey '^L' clear-screen-scrollback

  # ── CRM shortcut ─────────────────────────────────────────────────────────────
  # usage: lead-status "Name" sent   (moves lead to SENT section with today's date)
  lead-status() {
    local name="''${1}" section="''${2}" crm="$HOME/projects/boreal-leads/crm.md"
    local today=$(date '+%Y-%m-%d')
    echo "- [$today] $name — (update details in crm.md)" >> "$crm"
    echo "Added to CRM: $name — remember to move to correct section in crm.md"
  }

  # ── Compounding tools ────────────────────────────────────────────────────────

  # checkpoint: capture session state for zero-cost re-entry
  # usage: checkpoint "working on X, next: Y"
  checkpoint() {
    local note="''${*:-cwd: $PWD}"
    local ts=$(date '+%Y-%m-%d %H:%M')
    echo "- [$ts] $note" >> "$HOME/.session-state.md"
    echo "Saved: $note"
  }

  # director staleness guard — warn if Track A/B state is drifting
  _director_guard() {
    local state="$HOME/.claude/projects/-home-merulox/memory/director_state.md"
    if [[ -f "$state" ]]; then
      local age=$(( ($(date +%s) - $(stat -c %Y "$state")) / 86400 ))
      if (( age >= 3 )); then
        echo "⚠  Director state: ''${age}d stale — run: director"
      fi
    fi
  }
  _director_guard

  # t: quick task capture → tasks.md
  # usage: t buy milk              (undated)
  #        t 2026-04-10 call X     (dated)
  t() {
    local tasks="$HOME/obsidian/system/tasks.md"
    local body="''${*}"
    if [[ -z "$body" ]]; then
      echo "usage: t [YYYY-MM-DD] task description"
      return 1
    fi
    # Detect leading date
    if [[ "$body" =~ ^([0-9]{4}-[0-9]{2}-[0-9]{2})\ (.+)$ ]]; then
      local line="- [ ] ''${BASH_REMATCH[1]} | ''${BASH_REMATCH[2]}"
    else
      local line="- [ ] $body"
    fi
    # Insert after ## Backlog header
    if grep -q "## Backlog" "$tasks" 2>/dev/null; then
      sed -i "s|## Backlog|## Backlog\n$line|" "$tasks"
    else
      echo "$line" >> "$tasks"
    fi
    echo "Added: $line"
  }

  alias claude-dangerous='claude --dangerously-skip-permissions'

  # ── Full session manager — Ctrl+\ ───────────────────────────────────────────
  # All sessions grouped by type. K inside the picker nukes orphans.
  # Icons: ⬛ main  🤖 claude (cc-)  📁 other
  _tmux_session_mgr() {
    local chosen session_name ts
    local -a lines

    while IFS= read -r s; do
      if [[ "$s" == "main" ]]; then
        lines+=("⬛ main|main")
      elif [[ "$s" == cc-* ]]; then
        lines+=("🤖 ''${s#cc-}|$s")
      else
        lines+=("📁 $s|$s")
      fi
    done < <(tmux list-sessions -F "#{session_name}" 2>/dev/null | sort)
    lines+=("✨ [new session]|__new__")

    chosen=$(printf '%s\n' "''${lines[@]}" \
      | fzf --height=50% --reverse --border=rounded \
            --color="bg:#080a0c,fg:#dde4ed,hl:#22d3ee,border:#1c2128" \
            --header="Sessions | K=nuke orphans | Enter=switch | Ctrl-C=cancel" \
            --prompt="  " \
            --delimiter='|' --with-nth=1 \
            --bind "k:execute-silent(tmux-nuke-orphans)+reload(tmux list-sessions -F '#{session_name}' | sort | awk '{if(\$0==\"main\")print \"⬛ main|main\"; else if(\$0~/^cc-/)print \"🤖 \" substr(\$0,4) \"|\" \$0; else print \"📁 \" \$0 \"|\" \$0}' && echo '✨ [new session]|__new__')")
    [[ -z "$chosen" ]] && zle redisplay && return

    session_name="''${chosen#*|}"
    if [[ "$session_name" == "__new__" ]]; then
      ts=$(date +%m%d%H%M)
      tmux new-session -d -s "cc-auto-$ts" 2>/dev/null
      tmux switch-client -t "cc-auto-$ts"
    else
      tmux switch-client -t "$session_name"
    fi
    zle reset-prompt
  }
  zle -N _tmux_session_mgr
  bindkey '^\' _tmux_session_mgr

  # ── Claude session picker — Ctrl+G ──────────────────────────────────────────
  # Always inside tmux (enforced above), so switching is always switch-client.
  # New session: auto-named, created inline, switched to immediately.
  _claude_session_picker() {
    local sessions NEW chosen name ts
    sessions=$(tmux list-sessions -F "#{session_name}" 2>/dev/null | grep "^cc-" | sed 's/^cc-//')
    NEW="  [+ New session (auto-named)]"
    chosen=$(printf "%s\n%s\n" "$sessions" "$NEW" \
      | fzf --height=40% --reverse --border=rounded \
            --color="bg:#080a0c,fg:#dde4ed,hl:#22d3ee,border:#1c2128" \
            --header="Claude sessions | Enter=switch | Ctrl-C=cancel" \
            --prompt="  ")
    [[ -z "$chosen" ]] && zle redisplay && return
    if [[ "$chosen" == *"New session"* ]]; then
      ts=$(date +%m%d%H%M)
      name="auto-$ts"
      tmux new-session -d -s "cc-$name" "claude" 2>/dev/null
      tmux switch-client -t "cc-$name"
    else
      name="''${chosen%% *}"
      tmux switch-client -t "cc-$name"
    fi
    zle reset-prompt
  }
  zle -N _claude_session_picker
  bindkey '^G' _claude_session_picker

  '';

};

  programs.tmux = {
    enable = true;
    terminal = "tmux-256color";
    historyLimit = 50000;
    keyMode = "vi";
    baseIndex = 1;
    escapeTime = 0;

    plugins = with pkgs.tmuxPlugins; [
      {
        plugin = resurrect;
        extraConfig = ''
          set -g @resurrect-capture-pane-contents 'on'
          set -g @resurrect-strategy-vim 'session'
          set -g @resurrect-strategy-nvim 'session'
        '';
      }
      {
        plugin = continuum;
        extraConfig = ''
          set -g @continuum-restore 'on'
          set -g @continuum-save-interval '3'
        '';
      }
    ];

    extraConfig = ''
      # Prefix: Ctrl-A (like screen)
      unbind C-b
      set -g prefix C-a
      bind C-a send-prefix

      # True color support
      set -ga terminal-overrides ",*256col*:Tc"
      set -ga terminal-overrides ",alacritty:Tc"

      # Mouse support
      set -g mouse on

      # Clipboard integration
      set -g set-clipboard on
      set -as terminal-features ',wezterm:clipboard'

      # Split panes using | and -
      bind | split-window -h -c "#{pane_current_path}"
      bind - split-window -v -c "#{pane_current_path}"
      unbind '"'
      unbind %

      # New window keeps current path
      bind c new-window -c "#{pane_current_path}"

      # Reload config
      bind r source-file ~/.config/tmux/tmux.conf \; display "Config reloaded!"

      # Pane navigation (vim-style)
      bind h select-pane -L
      bind j select-pane -D
      bind k select-pane -U
      bind l select-pane -R

      # Resize panes
      bind -r H resize-pane -L 5
      bind -r J resize-pane -D 5
      bind -r K resize-pane -U 5
      bind -r L resize-pane -R 5

      # Nuke orphan sessions from the session chooser
      bind -T choose-tree K run-shell "tmux-nuke-orphans"

      # Status bar
      set -g status-position bottom
      set -g status-style bg=colour235,fg=colour136
      set -g status-left "#[fg=colour226,bold] #S "
      set -g status-right "#[fg=colour136]%H:%M %d-%b "
      set -g status-left-length 30
      set -g window-status-current-style fg=colour226,bold

      # Keybinding reference (second status row)
      set -g status 2
      set -g status-format[1] "#[bg=colour233,fg=colour240,align=centre] PANES: | h-split  - v-split  hjkl nav  HJKL resize  z zoom  x kill  q show#  {/} swap  Space layout  WIN: c new  w picker  n/p ±1  1-9 jump  , rename  & kill  SES: s list  \$ rename  d detach  [: copy-mode (vi keys)  ]: paste  r reload  : cmd  ? all-keys  K nuke-orphan"
    '';
  };


  # neovim
   programs.neovim = {
   enable = true;
   defaultEditor = true;
   vimAlias = true;
   withRuby = false;
   withPython3 = false;
   extraConfig = ''
     set relativenumber 
     set number
     nmap <Enter> o<ESC> 
     nmap <S-Enter> O<ESC>
     map <C-S-Tab> gT
     map <C-Tab> gt
   '';
   plugins = with pkgs.vimPlugins; [
   YankRing-vim
   vim-lastplace
   vim-cool
   indentLine
   vim-numbertoggle
   SudoEdit-vim
    { plugin = vim-startify;
      type = "viml";
     config = "let g:startify_change_to_vcs_root = 0";
     }
    ];
   };


  # Desktop Entries
  xdg.desktopEntries = {
    musicbee = {
      name = "MusicBee";
      genericName = "Music Player";
      exec = "WINEPREFIX=/home/merulox/MusicBeePrefix wine /home/merulox/MusicBeePrefix/drive_c/users/merulox/AppData/Roaming/Microsoft/Windows/Start Menu/Programs/MusicBee/MusicBee.lnk";
      terminal = false;
    };
  };

  # fzf
  programs.fzf = {
  enable = true;
  enableZshIntegration = true;  # handles keybindings and completion automatically
  };


  # zoxide
  programs.zoxide.enable = true;

  # navi
  programs.navi.enable = true;

  # ncmpcpp
 # programs.ncmpcpp = {
 # enable = true;
 # settings = {ncmpcpp_directory = "/etc/nixos/ncmpcpp";};
 # };

  # virt-manager code snippet
  dconf.settings = {
  "org/virt-manager/virt-manager/connections" = {
    autoconnect = ["qemu:///system"];
    uris = ["qemu:///system"];
   };
  };

  # mpd
  services.mpd = {
  enable = true;
  musicDirectory = "/mnt/data/Audio/Music";
  dbFile = "~/mpd/tag_cache";
  };
  
  # Darkman
  services.darkman = {
  enable = true;
  settings = {
    lat = 46.5;
    lng = -72.7;
    useGeoclue = false;
  };
  lightModeScripts = {
    gtk = ''
      gsettings set org.gnome.desktop.interface color-scheme prefer-light
      gsettings set org.gnome.desktop.interface gtk-theme "Arc"
    '';
    alacritty = ''
      sed -i 's/colors: \*dark/colors: *light/' ~/.config/alacritty/alacritty.toml
    '';
  };
  darkModeScripts = {
    gtk = ''
      gsettings set org.gnome.desktop.interface color-scheme prefer-dark
      gsettings set org.gnome.desktop.interface gtk-theme "Arc-Dark"
    '';
    alacritty = ''
      sed -i 's/colors: \*light/colors: *dark/' ~/.config/alacritty/alacritty.toml
    '';
  };
};
  # Alacritty config managed via ~/.config/alacritty/alacritty.toml (standalone, not home-manager)
  # darkman scripts modify it directly with sed so it cannot be a Nix store symlink
  # programs.alacritty = {
  # enable = true;
  # settings = {
  #    font = { normal.family = "Terminess Nerd Font Mono" ; size = 10; }; # was: termsyn size 18
  #    #colors = with config.colorScheme.colors; {
  #    # bright = {
  #    #   black = "0x${base00}";
  #    #   blue = "0x${base0D}";
  #    #   cyan = "0x${base0C}";
  #    #   green = "0x${base0B}";
  #    #   magenta = "0x${base0E}";
  #    #   red = "0x${base08}";
  #    #   white = "0x${base06}";
  #    #   yellow = "0x${base09}";
  #    # };
  #    # cursor = {
  #    #   cursor = "0x${base06}";
  #    #   text = "0x${base06}";
  #    # };
  #    # normal = {
  #    #   black = "0x${base00}";
  #    #   blue = "0x${base0D}";
  #    #   cyan = "0x${base0C}";
  #    #   green = "0x${base0B}";
  #    #   magenta = "0x${base0E}";
  #    #   red = "0x${base08}";
  #    #   white = "0x${base06}";
  #    #   yellow = "0x${base0A}";
  #    # };
  #    # primary = {
  #    #   background = "0x${base00}";
  #    #   foreground = "0x${base06}";
  #    # };
  #  # };
  #  };
  # };
  
  # Picom
  services.picom = {
   enable = true;
   activeOpacity = .98;
   inactiveOpacity = .92;
   shadow = true;
   settings = {
    blur =
    { method = "gaussian";
      size = 10;
      deviation = 5.0;
      use-ewmh-active-win = true;
     };
   };
   fadeExclude = [
     "window_type *= 'menu'"
     "name ~= 'vivaldi$'"
   ];
   opacityRules = [
     "100:class_g = 'mpv'"
     "100:class_g = 'gl'"
     "100:class_g = 'i3lock'"
     "100:class_g = 'vivaldi-stable'"
   ];
   
  };

  # Services
  services.flameshot.enable = true;
  services.dunst = {
   enable = true;
   configFile = "/etc/nixos/dunstrc";
  };
  services.redshift = {
  enable = true;
  duskTime = "19:30-19:40";
  dawnTime = "4:00-4:30";
  temperature.day = 5500;
  temperature.night = 2000;
  settings.brightness.day = 0.77;
  settings.brightness.night = 0.55;
  tray = true;
  };

  # Fontconfig — termsyn fallback to JetBrains Nerd Font for missing glyphs
  xdg.configFile."fontconfig/fonts.conf" = {
    force = true;
    text = ''
      <?xml version="1.0" encoding="UTF-8"?>
      <!DOCTYPE fontconfig SYSTEM "fonts.dtd">
      <fontconfig>
          <match target="font">
              <edit name="antialias" mode="assign">
                  <bool>false</bool>
              </edit>
              <edit name="hinting" mode="assign">
                  <bool>false</bool>
              </edit>
              <edit name="hintstyle" mode="assign">
                  <const>hintnone</const>
              </edit>
              <edit name="rgba" mode="assign">
                  <const>none</const>
              </edit>
              <edit name="autohint" mode="assign">
                  <bool>false</bool>
              </edit>
              <edit name="lcdfilter" mode="assign">
                  <const>lcdnone</const>
              </edit>
              <edit name="dpi" mode="assign">
                  <double>102</double>
              </edit>
          </match>
          <alias>
            <family>termsyn</family>
            <prefer>
              <family>Termsyn</family>
              <family>Terminess Nerd Font Mono</family>
            </prefer>
          </alias>
      </fontconfig>
    '';
  };


  # MIME type defaults
  xdg.mimeApps = {
    enable = true;
    defaultApplications = {
      "image/png"                = "viewnior.desktop";
      "image/jpeg"               = "viewnior.desktop";
      "image/gif"                = "viewnior.desktop";
      "image/webp"               = "viewnior.desktop";
      "inode/directory"          = "org.kde.dolphin.desktop";
      "video/mp4"                = "mpv.desktop";
      "video/mkv"                = "mpv.desktop";
      "video/x-matroska"         = "mpv.desktop";
      "audio/mpeg"               = "mpv.desktop";
      "application/pdf"          = "org.kde.okular.desktop";
      "text/html"                = "brave-browser.desktop";
      "x-scheme-handler/http"    = "brave-browser.desktop";
      "x-scheme-handler/https"   = "brave-browser.desktop";
    };
  };

 # Desktop files
 xdg.desktopEntries.lunar-client = {
  name = "Lunar Client";
  exec = "__GL_THREADED_OPTIMIZATIONS=0 lunar-client";
  terminal = false;
  type = "Application";

 };

  # Path
  home.sessionPath = [
  "$HOME/.local/bin"
  "/usr/local/bin/"
  "$HOME/scripts"
  ];

  # Daily backup timers
  systemd.user.services.backup-r2 = {
    Unit.Description = "Restic backup to Cloudflare R2";
    Service = {
      Type = "oneshot";
      ExecStart = "/home/merulox/scripts/backup-now.sh";
    };
  };
  systemd.user.timers.backup-r2 = {
    Unit.Description = "Daily Restic backup to R2";
    Timer = {
      OnCalendar = "daily";
      Persistent = true;
    };
    Install.WantedBy = [ "timers.target" ];
  };

  systemd.user.services.backup-dotfiles = {
    Unit.Description = "Auto-commit and push dotfiles";
    Service = {
      Type = "oneshot";
      ExecStart = "/home/merulox/scripts/backup-dotfiles.sh";
    };
  };
  systemd.user.timers.backup-dotfiles = {
    Unit.Description = "Daily dotfiles push";
    Timer = {
      OnCalendar = "daily";
      Persistent = true;
    };
    Install.WantedBy = [ "timers.target" ];
  };

  # Anthropic changelog watcher — checks for new features, evaluates integration impact
  systemd.user.services.brain-watch-anthropic = {
    Unit.Description = "Check Anthropic changelog for new features";
    Service = {
      Type = "oneshot";
      ExecStart = "/home/merulox/scripts/brain-watch-anthropic";
      Environment = "PATH=/home/merulox/scripts:/run/current-system/sw/bin:/home/merulox/.nix-profile/bin";
    };
  };
  systemd.user.timers.brain-watch-anthropic = {
    Unit.Description = "Daily Anthropic changelog check";
    Timer = {
      OnCalendar = "daily";
      Persistent = true;
    };
    # Disabled by Genesis freeze audit: autonomous API/agent timer.
    # Re-enable with: Install.WantedBy = [ "timers.target" ];
  };

  # brain-merge-domains — weekly domain bundle deduplication
  systemd.user.services.brain-merge-domains = {
    Unit.Description = "Merge near-duplicate Obsidian domain bundles";
    Service = {
      Type = "oneshot";
      ExecStart = "/home/merulox/scripts/brain-merge-domains --auto";
      Environment = "PATH=/home/merulox/scripts:/run/current-system/sw/bin:/home/merulox/.nix-profile/bin";
    };
  };
  systemd.user.timers.brain-merge-domains = {
    Unit.Description = "Weekly domain bundle merge";
    Timer = {
      OnCalendar = "Sun *-*-* 04:00:00";
      Persistent = true;
    };
    # Disabled by Genesis freeze audit: autonomous API/agent timer.
    # Re-enable with: Install.WantedBy = [ "timers.target" ];
  };

  # brain-resolve — nightly conflict resolution (processes up to 10 conflicts)
  systemd.user.services.brain-resolve = {
    Unit.Description = "Resolve open Obsidian vault conflicts";
    Service = {
      Type = "oneshot";
      ExecStart = "/home/merulox/scripts/brain-resolve --auto --limit 10";
      Environment = "PATH=/home/merulox/scripts:/run/current-system/sw/bin:/home/merulox/.nix-profile/bin";
    };
  };
  systemd.user.timers.brain-resolve = {
    Unit.Description = "Nightly conflict resolution";
    Timer = {
      OnCalendar = "daily";
      Persistent = true;
    };
    # Disabled by Genesis freeze audit: autonomous API/agent timer.
    # Re-enable with: Install.WantedBy = [ "timers.target" ];
  };

  # brain-promote — weekly inbox → graph promotion
  systemd.user.services.brain-promote = {
    Unit.Description = "Promote high-value inbox notes to knowledge graph";
    Service = {
      Type = "oneshot";
      ExecStart = "/home/merulox/scripts/brain-promote --top 10";
      Environment = "PATH=/home/merulox/scripts:/run/current-system/sw/bin:/home/merulox/.nix-profile/bin";
    };
  };
  systemd.user.timers.brain-promote = {
    Unit.Description = "Weekly inbox promotion";
    Timer = {
      OnCalendar = "Mon *-*-* 04:30:00";
      Persistent = true;
    };
    # Disabled by Genesis freeze audit: autonomous agent timer.
    # Re-enable with: Install.WantedBy = [ "timers.target" ];
  };

  # brain-loop — nightly Karpathy autoresearch (fills knowledge gaps, ingests 3 videos)
  systemd.user.services.brain-loop = {
    Unit.Description = "Autoresearch loop: detect gaps, ingest YouTube content";
    Service = {
      Type = "oneshot";
      ExecStart = "/home/merulox/scripts/brain-loop --limit 3";
      Environment = "PATH=/home/merulox/scripts:/run/current-system/sw/bin:/home/merulox/.nix-profile/bin";
      TimeoutStartSec = "900";
    };
  };
  systemd.user.timers.brain-loop = {
    Unit.Description = "Nightly autoresearch loop";
    Timer = {
      OnCalendar = "daily";
      Persistent = true;
    };
    # Disabled by Genesis freeze audit: autonomous API/agent timer.
    # Re-enable with: Install.WantedBy = [ "timers.target" ];
  };

  # brain-fill — repair broken wikilinks by creating missing graph nodes
  systemd.user.services.brain-fill = {
    Unit.Description = "Fill missing graph nodes from broken wikilinks";
    Service = {
      Type = "oneshot";
      ExecStart = "/home/merulox/scripts/brain-fill";
      Environment = "PATH=/home/merulox/scripts:/run/current-system/sw/bin:/home/merulox/.nix-profile/bin";
      TimeoutStartSec = "300";
    };
  };
  systemd.user.timers.brain-fill = {
    Unit.Description = "Weekly graph topology repair";
    Timer = {
      OnCalendar = "Wed *-*-* 05:00:00";
      Persistent = true;
    };
    # Disabled by Genesis freeze audit: autonomous API/agent timer.
    # Re-enable with: Install.WantedBy = [ "timers.target" ];
  };

  # brain-synthesize — auto-update synthesis-boreal.md from accumulated evidence
  systemd.user.services.brain-synthesize = {
    Unit.Description = "Auto-update Boreal synthesis from master-claims and dialogues";
    Service = {
      Type = "oneshot";
      ExecStart = "/home/merulox/scripts/brain-synthesize";
      Environment = "PATH=/home/merulox/scripts:/run/current-system/sw/bin:/home/merulox/.nix-profile/bin";
      TimeoutStartSec = "120";
    };
  };
  systemd.user.timers.brain-synthesize = {
    Unit.Description = "Weekly synthesis update";
    Timer = {
      OnCalendar = "Tue *-*-* 05:30:00";
      Persistent = true;
    };
    # Disabled by Genesis freeze audit: autonomous API/agent timer.
    # Re-enable with: Install.WantedBy = [ "timers.target" ];
  };

  # brain-backlog — flag stale NOW items in backlog.md
  systemd.user.services.brain-backlog = {
    Unit.Description = "Scan backlog for stale NOW items and alert";
    Service = {
      Type = "oneshot";
      ExecStart = "/home/merulox/scripts/brain-backlog";
      Environment = "PATH=/home/merulox/scripts:/run/current-system/sw/bin:/home/merulox/.nix-profile/bin";
      TimeoutStartSec = "30";
    };
  };
  systemd.user.timers.brain-backlog = {
    Unit.Description = "Daily backlog staleness check";
    Timer = {
      OnCalendar = "*-*-* 09:00:00";
      Persistent = true;
    };
    # Disabled by Genesis freeze audit: autonomous task/status timer.
    # Re-enable with: Install.WantedBy = [ "timers.target" ];
  };

  # brain-dialogue-auto — weekly autonomous dialogue on highest-leverage question
  systemd.user.services.brain-dialogue-auto = {
    Unit.Description = "Auto-pick and run strategic dialogue";
    Service = {
      Type = "oneshot";
      ExecStart = "/home/merulox/scripts/brain-dialogue-auto";
      Environment = "PATH=/home/merulox/scripts:/run/current-system/sw/bin:/home/merulox/.nix-profile/bin";
      TimeoutStartSec = "600";
    };
  };
  systemd.user.timers.brain-dialogue-auto = {
    Unit.Description = "Weekly autonomous strategic dialogue";
    Timer = {
      OnCalendar = "Fri *-*-* 06:00:00";
      Persistent = true;
    };
    # Disabled by Genesis freeze audit: autonomous API/agent timer.
    # Re-enable with: Install.WantedBy = [ "timers.target" ];
  };

  # twitter-watch — daily scrape of curated accounts → claims + ingest queue
  systemd.user.services.twitter-watch = {
    Unit.Description = "Daily Twitter/X account monitoring via nitter";
    Service = {
      Type = "oneshot";
      ExecStart = "/home/merulox/scripts/twitter-watch";
    };
  };
  systemd.user.timers.twitter-watch = {
    Unit.Description = "Daily twitter-watch timer";
    Timer = {
      OnCalendar = "*-*-* 08:00:00";
      Persistent = true;
    };
    Install.WantedBy = [ "timers.target" ];
  };

  # outreach-batch — daily automated cold SMS to next 10 untouched leads
  systemd.user.services.outreach-batch = {
    Unit.Description = "Daily automated cold SMS outreach";
    Service = {
      Type = "oneshot";
      ExecStart = "/home/merulox/scripts/outreach-batch --batch 10";
    };
  };
  systemd.user.timers.outreach-batch = {
    Unit.Description = "Daily outreach-batch timer";
    Timer = {
      OnCalendar = "Mon..Fri *-*-* 10:00:00";
      Persistent = true;
    };
    # Disabled by Genesis freeze audit: autonomous outbound outreach.
    # Re-enable with: Install.WantedBy = [ "timers.target" ];
  };
}
