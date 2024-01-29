{ config, pkgs, lib, ... }:
  let
  in
{
  home.username = "merulox";
  home.homeDirectory = "/home/merulox";
  home.stateVersion = "23.05";
  home.packages = [ pkgs.atool pkgs.httpie];

  # imports
  imports = [
    ./emacs.nix
  ];


  # home-manager
  programs.home-manager.enable = true;

  # fish
  programs.fish = {
   enable = true;
   interactiveShellInit = ''
     set fish_greeting # Disable greeting
   '';
   shellInit = lib.mkAfter "set fish_prompt_pwd_dir_length 0";
   plugins = [
      { name = "fzf-fish"; src = pkgs.fishPlugins.fzf.src; }
      { name = "done"; src = pkgs.fishPlugins.done.src; }
      { name = "pure"; src = pkgs.fishPlugins.pure.src; }
     #{ name = "tide"; src = pkgs.fishPlugins.tide.src; }
     #{ name = "hydro"; src = pkgs.fishPlugins.hydro.src; }
        
   ];
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
  programs.fzf.enable = true;

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
  


  # Alacritty
  programs.alacritty = {
  enable = true;
  settings = {
     font = { normal.family = "terminus" ; size = 14; };
     #colors = with config.colorScheme.colors; {
     # bright = {
     #   black = "0x${base00}";
     #   blue = "0x${base0D}";
     #   cyan = "0x${base0C}";
     #   green = "0x${base0B}";
     #   magenta = "0x${base0E}";
     #   red = "0x${base08}";
     #   white = "0x${base06}";
     #   yellow = "0x${base09}";
     # };
     # cursor = {
     #   cursor = "0x${base06}";
     #   text = "0x${base06}";
     # };
     # normal = {
     #   black = "0x${base00}";
     #   blue = "0x${base0D}";
     #   cyan = "0x${base0C}";
     #   green = "0x${base0B}";
     #   magenta = "0x${base0E}";
     #   red = "0x${base08}";
     #   white = "0x${base06}";
     #   yellow = "0x${base0A}";
     # };
     # primary = {
     #   background = "0x${base00}";
     #   foreground = "0x${base06}";
     # };
   # };
   };
  };
  
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

  # Default applications
 # xdg.mimeApps = {
 # enable = true;
 # defaultApplications = {
 #  "inode/directory" = ["org.kde.dolphin.desktop"]; 
 #  };
 # };
 
  # Path
  home.sessionPath = [
  "$HOME/.local/bin"
  "/usr/local/bin/"
  ];
}
