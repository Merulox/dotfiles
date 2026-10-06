{ config, pkgs, lib, ... }:
  let
    protonDriveCli = pkgs.stdenvNoCC.mkDerivation rec {
      pname = "proton-drive-cli";
      version = "0.7.0";
      src = pkgs.fetchurl {
        url = "https://proton.me/download/drive/cli/${version}/linux-x64/proton-drive";
        hash = "sha512-Wlr/y+wE6pJqMtEOI2wTQiJ/G21BbLeX+I+UOyxPHc9TtYl6EV8cGqnOjOkv1jfhxQvSI7BIZld2gfBYTszbxg==";
      };
      dontUnpack = true;
      dontStrip = true;
      nativeBuildInputs = [ pkgs.makeWrapper pkgs.patchelf ];
      installPhase = ''
        install -Dm755 "$src" "$out/bin/.proton-drive-unwrapped"
        patchelf \
          --set-interpreter "${pkgs.stdenv.cc.bintools.dynamicLinker}" \
          --set-rpath "${pkgs.lib.makeLibraryPath [ pkgs.stdenv.cc.cc.lib ]}" \
          "$out/bin/.proton-drive-unwrapped"
        makeWrapper "$out/bin/.proton-drive-unwrapped" "$out/bin/proton-drive" \
          --prefix LD_LIBRARY_PATH : "${pkgs.lib.makeLibraryPath [ pkgs.libsecret pkgs.glib pkgs.glib.dev ]}"
      '';
    };
    backupSecretsProton = pkgs.writeShellApplication {
      name = "backup-secrets-proton";
      runtimeInputs = [
        pkgs.coreutils
        pkgs.gnugrep
        pkgs.gnutar
        pkgs.libnotify
        protonDriveCli
      ];
      text = builtins.readFile ./workflow/bin/backup-secrets-proton;
    };
    grokBot = let
      version = "0.61.0";
      src = pkgs.fetchurl {
        url = "https://downloads.cursor.com/grokbot/stable/47a9d1df3a7d37aaa53d206ab2d1f9159a336223/linux/x64/Grok_Bot_${version}.AppImage";
        hash = "sha256-6Z9+fDRr0ddH1Cxf4EtAZoc+Lu1cSangdyE6jE/HiPk=";
      };
      appimageContents = pkgs.appimageTools.extractType2 {
        pname = "grok-bot";
        inherit version src;
      };
    in pkgs.appimageTools.wrapType2 {
      pname = "grok-bot";
      inherit version src;
      extraInstallCommands = ''
        install -m 444 -D ${appimageContents}/grok-bot.desktop \
          $out/share/applications/grok-bot.desktop
        install -m 444 -D ${appimageContents}/resources/icon.png \
          $out/share/icons/hicolor/512x512/apps/grok-bot.png
        substituteInPlace $out/share/applications/grok-bot.desktop \
          --replace-fail "Exec=AppRun --no-sandbox %U" "Exec=grok-bot %U"
      '';
    };
  in
{
  home.username = "merulox";
  home.homeDirectory = "/home/merulox";
  home.stateVersion = "24.05";
  home.packages = [ pkgs.atool pkgs.httpie pkgs.inotify-tools pkgs.khal pkgs.vdirsyncer pkgs.urbit protonDriveCli backupSecretsProton grokBot pkgs.vinegar ];

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
  unsetopt BEEP

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
      set -g allow-passthrough on

      # Mouse support
      set -g mouse on
      set -g bell-action none
      set -g visual-bell off
      set -g visual-activity off
      set -g visual-silence off

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
    extraPackages = with pkgs; [
      bash-language-server
      lua-language-server
      nil
      nixpkgs-fmt
      pyright
      ripgrep
      stylua
      typescript-language-server
      vscode-langservers-extracted
    ];
    initLua = ''
      vim.g.mapleader = " "
      vim.g.maplocalleader = " "

      vim.opt.number = true
      vim.opt.relativenumber = true
      vim.opt.mouse = "a"
      vim.opt.ignorecase = true
      vim.opt.smartcase = true
      vim.opt.signcolumn = "yes"
      vim.opt.termguicolors = true
      vim.opt.updatetime = 250
      vim.opt.completeopt = { "menu", "menuone", "noselect" }
      vim.opt.expandtab = true
      vim.opt.shiftwidth = 2
      vim.opt.tabstop = 2

      vim.keymap.set("n", "<Enter>", "o<Esc>", { silent = true })
      vim.keymap.set("n", "<S-Enter>", "O<Esc>", { silent = true })
      vim.keymap.set("n", "<C-S-Tab>", "gT", { silent = true })
      vim.keymap.set("n", "<C-Tab>", "gt", { silent = true })

      vim.keymap.set("n", "<leader>ff", "<cmd>Telescope find_files<cr>", { desc = "Find files" })
      vim.keymap.set("n", "<leader>fg", "<cmd>Telescope live_grep<cr>", { desc = "Live grep" })
      vim.keymap.set("n", "<leader>fb", "<cmd>Telescope buffers<cr>", { desc = "Buffers" })
      vim.keymap.set("n", "<leader>fh", "<cmd>Telescope help_tags<cr>", { desc = "Help tags" })
      vim.keymap.set("n", "<leader>e", "<cmd>NvimTreeToggle<cr>", { desc = "File tree" })
      vim.keymap.set("n", "<leader>q", vim.diagnostic.setloclist, { desc = "Diagnostics list" })

      require("nvim-tree").setup({
        view = { width = 34 },
        renderer = { group_empty = true },
        filters = { dotfiles = false },
      })

      require("lualine").setup({
        options = {
          theme = "auto",
          component_separators = "",
          section_separators = "",
        },
      })

      require("telescope").setup({
        defaults = {
          mappings = {
            i = {
              ["<C-j>"] = "move_selection_next",
              ["<C-k>"] = "move_selection_previous",
            },
          },
        },
      })

      require("gitsigns").setup()

      require("nvim-treesitter").setup({})

      vim.api.nvim_create_autocmd("FileType", {
        pattern = {
          "bash",
          "css",
          "html",
          "javascript",
          "javascriptreact",
          "json",
          "lua",
          "markdown",
          "nix",
          "python",
          "sh",
          "toml",
          "typescript",
          "typescriptreact",
          "vim",
          "yaml",
        },
        callback = function()
          pcall(vim.treesitter.start)
          vim.bo.indentexpr = "v:lua.require'nvim-treesitter'.indentexpr()"
        end,
      })

      local cmp = require("cmp")
      local luasnip = require("luasnip")
      require("luasnip.loaders.from_vscode").lazy_load()

      cmp.setup({
        snippet = {
          expand = function(args)
            luasnip.lsp_expand(args.body)
          end,
        },
        mapping = cmp.mapping.preset.insert({
          ["<C-b>"] = cmp.mapping.scroll_docs(-4),
          ["<C-f>"] = cmp.mapping.scroll_docs(4),
          ["<C-Space>"] = cmp.mapping.complete(),
          ["<C-e>"] = cmp.mapping.abort(),
          ["<CR>"] = cmp.mapping.confirm({ select = true }),
          ["<Tab>"] = cmp.mapping(function(fallback)
            if cmp.visible() then
              cmp.select_next_item()
            elseif luasnip.expand_or_jumpable() then
              luasnip.expand_or_jump()
            else
              fallback()
            end
          end, { "i", "s" }),
          ["<S-Tab>"] = cmp.mapping(function(fallback)
            if cmp.visible() then
              cmp.select_prev_item()
            elseif luasnip.jumpable(-1) then
              luasnip.jump(-1)
            else
              fallback()
            end
          end, { "i", "s" }),
        }),
        sources = cmp.config.sources({
          { name = "nvim_lsp" },
          { name = "luasnip" },
          { name = "path" },
        }, {
          { name = "buffer" },
        }),
      })

      local capabilities = require("cmp_nvim_lsp").default_capabilities()

      local servers = {
        bashls = {},
        cssls = {},
        html = {},
        jsonls = {},
        lua_ls = {
          settings = {
            Lua = {
              diagnostics = { globals = { "vim" } },
              workspace = { checkThirdParty = false },
            },
          },
        },
        nil_ls = {},
        pyright = {},
        ts_ls = {},
      }

      for name, config in pairs(servers) do
        config.capabilities = capabilities
        vim.lsp.config(name, config)
        vim.lsp.enable(name)
      end

      vim.api.nvim_create_autocmd("LspAttach", {
        callback = function(event)
          local opts = { buffer = event.buf }
          vim.keymap.set("n", "gd", vim.lsp.buf.definition, opts)
          vim.keymap.set("n", "gr", vim.lsp.buf.references, opts)
          vim.keymap.set("n", "K", vim.lsp.buf.hover, opts)
          vim.keymap.set("n", "<leader>rn", vim.lsp.buf.rename, opts)
          vim.keymap.set({ "n", "v" }, "<leader>ca", vim.lsp.buf.code_action, opts)
          vim.keymap.set("n", "<leader>f", function()
            vim.lsp.buf.format({ async = true })
          end, opts)
        end,
      })
    '';
    plugins = with pkgs.vimPlugins; [
      YankRing-vim
      vim-lastplace
      vim-cool
      vim-numbertoggle
      SudoEdit-vim
      cmp-buffer
      cmp-nvim-lsp
      cmp-path
      cmp_luasnip
      friendly-snippets
      gitsigns-nvim
      lualine-nvim
      luasnip
      nvim-cmp
      nvim-lspconfig
      nvim-tree-lua
      nvim-treesitter
      (nvim-treesitter.withPlugins (p: with p; [
        bash
        css
        html
        javascript
        json
        lua
        markdown
        markdown_inline
        nix
        python
        regex
        toml
        tsx
        typescript
        vim
        vimdoc
        yaml
      ]))
      telescope-nvim
      vim-nix
      {
        plugin = vim-startify;
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

  home.file.".inputrc".text = ''
    set bell-style none
  '';

  # ncmpcpp
 # programs.ncmpcpp = {
 # enable = true;
 # settings = {ncmpcpp_directory = "/etc/nixos/ncmpcpp";};
 # };

  # virt-manager code snippet
  dconf.settings = {
  "org/gnome/desktop/sound" = {
    event-sounds = false;
    input-feedback-sounds = false;
  };
  "org/gnome/desktop/wm/preferences" = {
    audible-bell = false;
    visual-bell = false;
  };
  "org/virt-manager/virt-manager/connections" = {
    autoconnect = ["qemu:///system"];
    uris = ["qemu:///system"];
   };
  };

  xdg.configFile."gtk-3.0/settings.ini" = {
    force = true;
    text = ''
      [Settings]
      gtk-theme-name=Adwaita-dark
      gtk-application-prefer-dark-theme=false
      gtk-icon-theme-name=gnome
      gtk-cursor-theme-name=miku-cursor-linux
      gtk-cursor-theme-size=16
      gtk-font-name=Noto Sans,  10
      gtk-xft-antialias=1
      gtk-xft-hinting=1
      gtk-xft-hintstyle=hintmedium
      gtk-xft-rgba=none
      gtk-xft-dpi=109514
      gtk-overlay-scrolling=true
      gtk-menu-images=true
      gtk-button-images=true
      gtk-enable-event-sounds=false
      gtk-enable-input-feedback-sounds=false
    '';
  };

  xdg.configFile."gtk-4.0/settings.ini" = {
    force = true;
    text = ''
      [Settings]
      gtk-theme-name=Adwaita
      gtk-application-prefer-dark-theme=false
      gtk-icon-theme-name=gnome
      gtk-cursor-theme-name=miku-cursor-linux
      gtk-cursor-theme-size=16
      gtk-font-name=Noto Sans,  10
      gtk-xft-antialias=1
      gtk-xft-hinting=1
      gtk-xft-hintstyle=hintmedium
      gtk-xft-rgba=none
      gtk-xft-dpi=109514
      gtk-overlay-scrolling=true
      gtk-enable-event-sounds=false
      gtk-enable-input-feedback-sounds=false
    '';
  };

  xdg.configFile."xsettingsd/xsettingsd.conf" = {
    force = true;
    text = ''
      Net/ThemeName "Adwaita-dark"
      Gdk/UnscaledDPI 98304
      Gdk/WindowScalingFactor 1
      Gtk/EnableAnimations 1
      Gtk/DecorationLayout "icon:minimize,maximize,close"
      Gtk/PrimaryButtonWarpsSlider 0
      Gtk/ToolbarStyle 3
      Gtk/MenuImages 1
      Gtk/ButtonImages 1
      Gtk/CursorThemeSize 24
      Gtk/CursorThemeName "breeze_cursors"
      Net/IconThemeName "Papirus-Light"
      Gtk/FontName "Noto Sans,  10"
      Net/EnableEventSounds 0
      Net/EnableInputFeedbackSounds 0
    '';
  };

  # mpd
  services.mpd = {
  enable = false;
  };
  
  # Darkman
  services.darkman = {
  enable = true;
  settings = {
    lat = 46.5;
    lng = -72.7;
    usegeoclue = false;
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
      "x-scheme-handler/grokbot" = "grok-bot.desktop";
      "x-scheme-handler/sand"    = "grok-bot.desktop";
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
  "$HOME/.rokit/bin" # Roblox toolchain shims (pins live in each project rokit.toml)
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

  systemd.user.services.backup-secrets-proton = {
    Unit.Description = "Backup .secrets bootstrap archive to Proton Drive";
    Service = {
      Type = "oneshot";
      Environment = [ "PROTON_DRIVE_BIN=${protonDriveCli}/bin/proton-drive" ];
      ExecStart = "${backupSecretsProton}/bin/backup-secrets-proton";
    };
  };
  systemd.user.timers.backup-secrets-proton = {
    Unit.Description = "Daily .secrets backup to Proton Drive";
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

  # Receipt-grounded autonomous SOL/USDC canary — fixed bankroll, no auto-replenishment
  systemd.user.services.agent-economy-live-canary = {
    Unit.Description = "Bounded OMP research and isolated Solana economic canary";
    Service = {
      Type = "oneshot";
      WorkingDirectory = "/home/merulox/projects/agent-economy-experiment/live_canary";
      ExecStart = "/run/current-system/sw/bin/python3 /home/merulox/projects/agent-economy-experiment/live_canary/canary.py cycle";
      Environment = "PATH=/home/merulox/.local/bin:/home/merulox/scripts:/run/current-system/sw/bin:/home/merulox/.nix-profile/bin";
      TimeoutStartSec = "600";
      UMask = "0077";
      NoNewPrivileges = true;
      PrivateTmp = true;
    };
  };
  systemd.user.timers.agent-economy-live-canary = {
    Unit.Description = "Run the autonomous SOL/USDC canary every 15 minutes";
    Timer = {
      OnBootSec = "2min";
      OnUnitActiveSec = "15min";
      AccuracySec = "30s";
      Persistent = true;
    };
    Install.WantedBy = [ "timers.target" ];
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
  # SYNTRA CJ qualification reply watcher — narrow Gmail thread → Telegram resume signal
  systemd.user.services.syntra-cj-email-watch = {
    Unit = {
      Description = "Watch the CJ supplier-qualification email thread";
      After = [ "network-online.target" ];
      Wants = [ "network-online.target" ];
    };
    Service = {
      Type = "oneshot";
      ExecStart = "/home/merulox/scripts/syntra-cj-email-watch";
      Environment = "PATH=/home/merulox/scripts:/run/current-system/sw/bin:/home/merulox/.nix-profile/bin";
    };
  };
  systemd.user.timers.syntra-cj-email-watch = {
    Unit.Description = "Poll the CJ supplier-qualification email thread";
    Timer = {
      OnBootSec = "2m";
      OnUnitActiveSec = "2m";
      Persistent = true;
    };
    Install.WantedBy = [ "timers.target" ];
  };


  # Genesis voice — local microphone/wake boundary, Realtime speech, proactive scheduler
  systemd.user.services.genesis-voice = {
    Unit = {
      Description = "Genesis ambient voice runtime (local wake gate + Realtime speech + bounded OMP)";
      After = [ "network-online.target" "pipewire.service" "wireplumber.service" ];
      Wants = [ "network-online.target" ];
    };
    Service = {
      Type = "simple";
      ExecStart = "/home/merulox/scripts/genesis-voice";
      Environment = "PATH=/home/merulox/scripts:/run/current-system/sw/bin:/home/merulox/.nix-profile/bin";
      Restart = "on-failure";
      RestartSec = "5";
      TimeoutStopSec = "10";
      UMask = "0077";
      StandardOutput = "journal";
      StandardError = "journal";
    };
    Install.WantedBy = [ "default.target" ];
  };

  # Keep the shared phone tmux workspace available whenever the lingering user manager starts.
  systemd.user.services.phone-tmux = {
    Unit.Description = "Persistent phone tmux workspace";
    Service = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = pkgs.writeShellScript "phone-tmux-start" ''
        set -eu
        socket_dir=/run/user/1000/tmux-1000
        ${pkgs.coreutils}/bin/mkdir -p "$socket_dir"
        ${pkgs.coreutils}/bin/chmod 700 "$socket_dir"
        socket="$socket_dir/default"
        ${pkgs.tmux}/bin/tmux -S "$socket" new-session -d -s phone "${pkgs.zsh}/bin/zsh -l" 2>/dev/null \
          || ${pkgs.tmux}/bin/tmux -S "$socket" has-session -t phone
      '';
    };
    Install.WantedBy = [ "default.target" ];
  };

}
