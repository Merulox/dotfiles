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
      { name = "done"; src= pkgs.fishPlugins.done; }  
        
   ];
  };

  # fzf
  programs.fzf.enable = true;

  # zoxide
  programs.zoxide.enable = true;

  # navi
  programs.navi.enable = true;

  # Alacritty
  programs.alacritty = {
  enable = true;
  settings = {
     font = { normal.family = "terminus" ; size = 14; };
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
  xdg.mimeApps.defaultApplications = {
  enable = true;
  defaultApplications = {
   "inode/directory" = ["org.kde.dolphin.desktop"]; 
   };
  };
 
  # Path
  home.sessionPath = [
  "$HOME/.local/bin"
  "/usr/local/bin/"
  ];
}
