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
   shellInit = lib.mkAfter "zoxide init fish | source";
   plugins = [
      { name = "fzf-fish"; src = pkgs.fishPlugins.fzf.src; }
   ];
  };

  # fzf
  programs.fzf.enable = true;

}
