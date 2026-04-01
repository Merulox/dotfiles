{ config, pkgs, lib, ... }:
  let
  in
{
  home.username = "merulox";
  home.homeDirectory = "/home/merulox";
  home.stateVersion = "24.05";
  home.packages = [ pkgs.atool pkgs.httpie];

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
  # manual prompt
    # autoload -U promptinit; promptinit
    # prompt pure

    # PURE_PROMPT_SYMBOL="%n@%m >"

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

  '';
};




  # neovim
   programs.neovim = {
   enable = true;
   defaultEditor = true;
   vimAlias = true;
   extraConfig = ''
     set relativenumber 
     set number
     nmap <Enter> o<ESC> 
     nmap <S-Enter> O<ESC>
     map <C-S-Tab> gT
     map <C-Tab> gt
   '';
   plugins = with pkgs.vimPlugins; [
   vim-nix
   yankring
   vim-lastplace
   vim-cool
   indentLine
   vim-numbertoggle
   SudoEdit-vim
    { plugin = vim-startify;
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
  extraConfig = ''
   audio_output {
     type "pulse"
     name "mpd"
   }
  '';
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
}
