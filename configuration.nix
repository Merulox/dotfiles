# Edit this configuration file to define what should be installed on
# your system.  Help is available in the configuration.nix(5) man page
# and in the NixOS manual (accessible by running ‘nixos-help’).
{ config, pkgs, lib, ... }:
let
  aagl-gtk-on-nix = import (builtins.fetchTarball "https://github.com/ezKEa/aagl-gtk-on-nix/archive/main.tar.gz");
in
{


  # Imports
  imports =
    [ # Include the results of the hardware scan.
      ./hardware-configuration.nix
      <home-manager/nixos>
      ./unstable.nix
      aagl-gtk-on-nix.module
    ];
  # Home-manager
  home-manager = {
    useGlobalPkgs = true;
    useUserPackages = true;
    users.merulox = import ./home.nix;
  };

  # Flakes
    nix = {
    package = pkgs.nixFlakes;
    extraOptions = ''
      experimental-features = nix-command flakes
    '';
  };

  # Opengl hardware
  hardware.opengl = {
    enable = true;
    driSupport = true;
    driSupport32Bit = true;
  };
  # Nvidia hardware
    hardware.nvidia = {

    # Modesetting is needed for most wayland compositors
    modesetting.enable = true;

    # Use the open source version of the kernel module
    # Only available on driver 515.43.04+
    open = true;

    # Enable the nvidia settings menu
    nvidiaSettings = true;

    # Optionally, you may need to select the appropriate driver version for your specific GPU.
    package = config.boot.kernelPackages.nvidiaPackages.stable;
  };
  # Nvidia drivers
  nixpkgs.config.allowUnfreePredicate = pkg:
    builtins.elem (lib.getName pkg) [
      "nvidia-x11"
    ];
  # Pulseaudio
  hardware.pulseaudio.enable = true;
  hardware.pulseaudio.extraConfig = "load-module module-combine-sink";
  hardware.bluetooth.enable = true;
  # Bootloader.
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  networking.hostName = "navi"; # Define your hostname.
  # networking.wireless.enable = true;  # Enables wireless support via wpa_supplicant.

  # Configure network proxy if necessary
  # networking.proxy.default = "http://user:password@proxy:port/";
  # networking.proxy.noProxy = "127.0.0.1,localhost,internal.domain";

  # Enable networking
  networking.networkmanager.enable = true;

  # Set your time zone.
  time.timeZone = "America/Toronto";

  # Select internationalisation properties.
  i18n.defaultLocale = "en_CA.UTF-8";

  # Configure keymap in X11
  services.xserver = {
    enable = true;
    layout = "us,fr";
    xkbVariant = "";
    displayManager.sddm.enable = true;
    windowManager.i3.enable = true; 
    videoDrivers = ["nvidia"];
 };

  # Define a user account. Don't forget to set a password with ‘passwd’.
  users.users.merulox = {
    isNormalUser = true;
    description = "merulox";
    extraGroups = [ "networkmanager" "wheel" ];
    packages = with pkgs; [];
  };
  # Trusted Users
  nix.settings.trusted-users = [ "root" "merulox" ];
  # Default Shell
  users.defaultUserShell = pkgs.fish;

  # Allow unfree packages
  nixpkgs.config.allowUnfree = true;


  # Environment variables
  environment.sessionVariables = rec {
  QT_QPA_PLATFORMTHEME = "qt5ct";
  XDG_CURRENT_DESKTOP = "kde";
};

  # Desktop integration portals
  xdg.portal.extraPortals = [ pkgs.libsForQt5.xdg-desktop-portal-kde ];
  xdg.portal.enable = true;
  # Fonts
  fonts.fonts = with pkgs; [
  terminus_font
];
  # List packages installed in system profile. To search, run:
  # $ nix search wget
  # System Packages
  environment.systemPackages = with pkgs; [
  vim # Do not forget to add an editor to edit configuration.nix! The Nano editor is also installed by default.
  wget
  git
  i3
  i3status
  i3blocks
  vivaldi  
  alacritty
  bitwarden
  thunderbird
  xdg-desktop-portal
  libsForQt5.xdg-desktop-portal-kde
  autotiling
  xfce.thunar
  ntfs3g  
  discord
  flameshot
  libsForQt5.qt5ct
  libsForQt5.kdialog
  gnumake
  dunst
  playerctl
  killall
  mpv
  vlc
  coreutils-full
  toybox
  libsForQt5.kate
  gnome-icon-theme
  ayu-theme-gtk
  arc-theme
  arc-kde-theme
  clementine
  wine
  winetricks
  dracula-theme
  neofetch
  ncpamixer
  pavucontrol
  rednotebook
  cinnamon.nemo
  cinnamon.nemo-fileroller
  libsForQt5.ark
  python38
  libGL
  gnome.gedit
  lxappearance
  libsForQt5.oxygen
  libsForQt5.oxygen-icons5
  clipmenu
  emojipick
  xdotool
  libsForQt5.qtcurve
  libsForQt5.qtstyleplugins
  variety
  libsForQt5.dolphin
  blueman
  rxvt-unicode-unwrapped-emoji
  feh
  nm-tray
  yt-dlp
  obsidian
  nix-index
  libGL
  libglvnd
  pkg-config
  calibre
  arandr
  j4-dmenu-desktop
  wgnord
  cider
  jq
  curl 
  wireguard-tools
  openresolv
  xkb-switch-i3
  xorg.xkill
  obs-studio
  anki-bin
  toipe
  ventoy-full
  zplug
  fish
  fishPlugins.fzf
  zoxide
  betterlockscreen
  ];

  # Overlays
 # nixpkgs.overlays = [ (import <nixpkgs> {}).overrideAttrs (oldAttrs: {
 #   modules = oldAttrs.modules // [ /etc/nixos/modules/nordvpn.nix ];
 # }) ];


  # Programs
  programs.fish.enable = true;

  # Shell Aliases
  environment.shellAliases = {
    update = "sudo nixos-rebuild switch"; i3config = "vim ~/.config/i3/config"; zshrc = "vim ~/.zshrc"; aliases = "vim ~/.aliases"; bconnect="~/.local/bin/bconnect"; dconnect = "~/.local/bin/dconnect"; conf = "cd ~/.config && cd"; rate = "xset r rate 300 25"; chmodall = "sudo chmod 777"; xlayout = "~/.config/i3/xrandr-layout.sh"; nconf = "sudo vim /etc/nixos/configuration.nix"; ll = "ls -l"; homenix = "sudo vim /etc/nixos/home.nix";}; 
 
  # Anime game launcher
  programs.anime-game-launcher.enable = true;

  # Flakes
  nix.settings.experimental-features = [ "nix-command" "flakes" ];

  # Some programs need SUID wrappers, can be configured further or are
  # started in user sessions.
  # programs.mtr.enable = true;
  # programs.gnupg.agent = {
  #   enable = true;
  #   enableSSHSupport = true;
  # };

  # List services that you want to enable:
    services.blueman.enable = true;    
    services.flatpak.enable = true;
    services.udisks2.enable = true;

  # Enable the OpenSSH daemon.
  # services.openssh.enable = true;

  # Open ports in the firewall.
    networking.firewall.allowedTCPPorts = [8080];
    networking.firewall.allowedUDPPorts = [8080];
  # Or disable the firewall altogether.
  #  networking.firewall.enable = false;

  # This value determines the NixOS release from which the default
  # settings for stateful data, like file locations and database versions
  # on your system were taken. It‘s perfectly fine and recommended to leave
  # this value at the release version of the first install of this system.
  # Before changing this value read the documentation for this option
  # (e.g. man configuration.nix or on https://nixos.org/nixos/options.html).
  system.stateVersion = "23.05"; # Did you read the comment?
  system.copySystemConfiguration = true;
}
