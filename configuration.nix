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
      "steam"
      "steam-original"
      "steam-run"
    ];
  # Pulseaudio
  hardware.pulseaudio.enable = true;
  hardware.pulseaudio.extraConfig = "load-module module-combine-sink";
  hardware.bluetooth.enable = true;
  # zsa
  hardware.keyboard.zsa.enable = true;
  # Bootloader.
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  # Opentabletdriver
  hardware.opentabletdriver.enable = true;
  hardware.opentabletdriver.daemon.enable = true;

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
    extraGroups = [ "networkmanager" "wheel" "plugdev" ];
    packages = with pkgs; [];
  };
  # Secrets Provider
  services.passSecretService.enable = true;
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
  carlito
  dejavu_fonts
  ipafont
  ttf_bitstream_vera
  ];

  fonts.fontconfig.defaultFonts = {
    monospace = [
      "DejaVu Sans Mono"
      "IPAGothic"
    ];
    sansSerif = [
      "DejaVu Sans"
      "IPAPGothic"
    ];
    serif = [
      "DejaVu Serif"
      "IPAPMincho"
    ];
  };
  #fonts.fontconfig.antialias = false; 
 


  # Overlays
 # nixpkgs.overlays = [ (import <nixpkgs> {}).overrideAttrs (oldAttrs: {
 #   modules = oldAttrs.modules // [ /etc/nixos/modules/nordvpn.nix ];
 # }) ];


  # Programs
  programs.fish.enable = true;

  # Steam
  programs.steam = {
  enable = true;
  remotePlay.openFirewall = true; # Open ports in the firewall for Steam Remote Play
  dedicatedServer.openFirewall = true; # Open ports in the firewall for Source Dedicated Server
  };

  # Shell Aliases
  environment.shellAliases = {
    update = "sudo nixos-rebuild switch"; i3config = "vim ~/.config/i3/config"; zshrc = "vim ~/.zshrc"; aliases = "vim ~/.aliases"; bconnect="~/.local/bin/bconnect"; dconnect = "~/.local/bin/dconnect"; conf = "cd ~/.config && cd"; rate = "xset r rate 300 25"; chmodall = "sudo chmod 777"; xlayout = "~/.config/i3/xrandr-layout.sh"; nconf = "sudo vim /etc/nixos/configuration.nix"; ll = "ls -l"; homenix = "sudo vim /etc/nixos/home.nix";}; 
 
  # Cachix
    nix.settings = {
      substituters = [ "https://ezkea.cachix.org" ];
      trusted-public-keys = [ "ezkea.cachix.org-1:ioBmUbJTZIKsHmWWXPe1FSFbeVe+afhfgqgTSNd34eI=" ];
    };
  

  # Anime Game Launcher
  programs.anime-game-launcher.enable = true;
  
  # Honkers Railway Launcher
  programs.honkers-railway-launcher.enable = true;

  # Flakes
  nix.settings.experimental-features = [ "nix-command" "flakes" ];

  # Japanese
  console.font = "Lat2-Terminus16";
  i18n.inputMethod = {
  enabled = "ibus";
  ibus.engines = with pkgs.ibus-engines; [mozc];
  };

  # Some programs need SUID wrappers, can be configured further or are
  # started in user sessions.
 #  programs.mtr.enable = true;
 #  programs.gnupg.agent = {
 #    enable = true;
 #    enableSSHSupport = true;
 #  };

  # List services that you want to enable:
    services.blueman.enable = true;    
    services.flatpak.enable = true;
    services.udisks2.enable = true;
    services.mullvad-vpn.enable = true;
    #services.flameshot.enable = true;
    #services.dunst.enable = true;

  # Printing
  services.printing.enable = true;
  services.printing.drivers = [ pkgs.brlaser pkgs.brgenml1lpr pkgs.brgenml1cupswrapper ];
  services.avahi.enable = true;
  services.avahi.nssmdns = true;
  # for a WiFi printer
  services.avahi.openFirewall = true;
 
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
  firefox
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
  libnotify
  glib
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
  libsForQt5.kio-extras
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
  artha
  libsForQt5.plasma-workspace
  libsForQt5.kcalc
  warpd
  zsa-udev-rules
  qbittorrent
  katawa-shoujo
  opentabletdriver
  mullvad-vpn
  shutter
  telegram-desktop
  nixos-option
  osu-lazer
  krita
  elementary-planner
  element-desktop
  nheko
  keepassxc
  psi-plus
  teamspeak5_client
  signal-desktop
  ];

}
