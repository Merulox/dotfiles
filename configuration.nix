# Edit this configuration file to define what should be installed on
# your system.  Help is available in the configuration.nix(5) man page
# and in the NixOS manual (accessible by running ‘nixos-help’).
{ config, pkgs, ... }:

{
  imports =
    [ # Include the results of the hardware scan.
      ./hardware-configuration.nix
      <home-manager/nixos>
      ./unstable.nix
    ];
  # Home-manager
  home-manager = {
    useGlobalPkgs = true;
    useUserPackages = true;
    users.merulox = import ./home.nix;
  };


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
    layout = "us";
    xkbVariant = "";
    displayManager.sddm.enable = true;
    windowManager.i3.enable = true; 
 };

  # Define a user account. Don't forget to set a password with ‘passwd’.
  users.users.merulox = {
    isNormalUser = true;
    description = "merulox";
    extraGroups = [ "networkmanager" "wheel" ];
    packages = with pkgs; [];
  };
  # Default Shell
  users.defaultUserShell = pkgs.zsh;

  # Allow unfree packages
  nixpkgs.config.allowUnfree = true;


  # Environment variables
  environment.sessionVariables = rec {
  QT_QPA_PLATFORMTHEME = "qt5ct";
};

  # Desktop integration portals
  xdg.portal.extraPortals = [ pkgs.xdg-desktop-portal-gtk ];
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
  autotiling
  xfce.thunar
  ntfs3g  
  discord
  flameshot
  libsForQt5.qt5ct
  zsh
  neofetch
  ncpamixer
  pavucontrol
  rednotebook
  cinnamon.nemo
  udisks
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
  ];

programs.zsh = {
  enable = true;
  shellAliases = {
    ll = "ls -l";
    update = "sudo nixos-rebuild switch"; i3config = "vim ~/.config/i3/config"; zshrc = "vim ~/.zshrc"; aliases = "vim ~/.aliases"; bconnect="~/.local/bin/bconnect"; dconnect = "~/.local/bin/dconnect"; conf = "cd ~/.config && cd"; rate = "xset r rate 300 25"; chmodall = "sudo chmod 777"; xlayout = "~/.config/i3/xrandr-layout.sh"; nconf = "sudo vim /etc/nixos/configuration.nix"; 
  };
};

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

  # Enable the OpenSSH daemon.
  # services.openssh.enable = true;

  # Open ports in the firewall.
    networking.firewall.allowedTCPPorts = [8080];
    networking.firewall.allowedUDPPorts = [8080];
  # Or disable the firewall altogether.
  # networking.firewall.enable = false;

  # This value determines the NixOS release from which the default
  # settings for stateful data, like file locations and database versions
  # on your system were taken. It‘s perfectly fine and recommended to leave
  # this value at the release version of the first install of this system.
  # Before changing this value read the documentation for this option
  # (e.g. man configuration.nix or on https://nixos.org/nixos/options.html).
  system.stateVersion = "23.05"; # Did you read the comment?
  system.copySystemConfiguration = true;
}
