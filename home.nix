{ config, pkgs, lib, ... }:

{
  home.username = "merulox";
  home.homeDirectory = "/home/merulox";
  home.stateVersion = "23.05";
  home.packages = [ pkgs.atool pkgs.httpie ];

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
   ];
  };

  # fzf
  programs.fzf.enable = true;

  # zoxide
  programs.zoxide.enable = true;

  # Alacritty
  programs.alacritty = {
  enable = true;
  settings = {
     font = { normal.family = "Terminus" ; size = 14; };
   };
  };

  # Services
  services.flameshot.enable = true;
  services.dunst = {
   enable = true;
   configFile = "/etc/nixos/dunstrc";
  };
  services.redshift = {
  enable = true;
  duskTime = "21:00-22:00";
  dawnTime = "3:00-3:30";
  temperature.day = 5500;
  temperature.night = 2000;
  settings.brightness.day = 0.77;
  settings.brightness.night = 0.55;
  tray = true;
  };
}
