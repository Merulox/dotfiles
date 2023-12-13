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


#  # Desktop Entries
#  xdg.desktopEntries = {
#    neovim = {
#      name = "nvim";
#      genericName = "neovim";
#      exec = "nvim";
#      terminal = true;
#      mimeType = [ "EDITOR" "SUDO_EDITOR" "VISUAL" ];
#    };
#  };

  # fzf
  programs.fzf.enable = true;

  # zoxide
  programs.zoxide.enable = true;

  # navi
  programs.navi.enable = true;

  # ncmpcpp
  programs.ncmpcpp.enable = true;
  programs.ncmpcpp.settings = {ncmpcpp_directory = "/etc/nixos/ncmpcpp";};
  
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
     };
   };
   fadeExclude = [
  "window_type *= 'menu'"
  "name ~= 'vivaldi$'"
  ];
  # opacityRules = [
  #   "100:WM_CLASS = 'mpv'"
  #   "100:WM_CLASS = 'betterlockscreen'"
  # ];
   
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
