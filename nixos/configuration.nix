# Edit this configuration file to define what should be installed on
# your system.  Help is available in the configuration.nix(5) man page
# and in the NixOS manual (accessible by running 'nixos-help').
{ config, pkgs, lib, ... }:
let
  aagl-gtk-on-nix = import (builtins.fetchTarball "https://github.com/ezKEa/aagl-gtk-on-nix/archive/main.tar.gz");
  nix-gaming = import (builtins.fetchTarball "https://github.com/fufexan/nix-gaming/archive/master.tar.gz");

in
{


  # Imports
  imports =
    [ # Include the results of the hardware scan.
      ./hardware-configuration.nix
      <home-manager/nixos>
      ./unstable.nix
      aagl-gtk-on-nix.module
      nix-gaming.nixosModules.pipewireLowLatency
    ];

  # Home-manager
  home-manager = {
    useGlobalPkgs = true;
    useUserPackages = true;
    users.merulox = import ./home.nix;
  };

  # Flakes
  nix.settings.experimental-features = [ "nix-command" "flakes" ];

  # Insecure packages
  nixpkgs.config.permittedInsecurePackages = [
   "electron-24.8.6"
  ];

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

  # Reboot / Shutdown
  boot.kernelParams = [
    "reboot=acpi;"

  ];

  # Nvidia drivers
  nixpkgs.config.allowUnfreePredicate = pkg:
    builtins.elem (lib.getName pkg) [
      "nvidia-x11"
      "steam"
      "steam-original"
      "steam-run"
    ];

  # invidious
 # services.invidious = { 
 #   enable = true;
 #   nginx.enable = false;
 #   port = 12345;

 #   # if you want to disable recommended videos
 #   settings = {
 #     default_user_preferences = {
 #       "related_videos" = false;
 #     };
 #   };
 # };

  # Pulseaudio
  #hardware.pulseaudio.enable = true;
  #hardware.pulseaudio.extraConfig = "load-module module-combine-sink";
  
  # PipeWire
  security.rtkit.enable = true;
  services.pipewire = {
   enable = true;
   alsa.enable = true;
   alsa.support32Bit = true;
   pulse.enable = true;
   lowLatency.enable = true;
  };

  # bluetooth 
  hardware.bluetooth.enable = true;
  # zsa
  hardware.keyboard.zsa.enable = true;
  # Bootloader.
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
  # podman
  virtualisation.podman.enable = true; # for distrobox
  #virtualisation.podman.rootless.enable = true;
  # Mount drive
   fileSystems."/mnt/data" =
    { device = "/dev/sda1";
      fsType = "ntfs-3g"; 
      options = [ "rw" "uid=1000"];
    };
  boot.supportedFilesystems = [ "ntfs" ];

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
  #i18n.supportedLocales = [
  #  "en_US.UTF-8/UTF-8"
  #  "ja_JP.UTF-8/UTF-8"
  #];

  # Configure keymap in X11
  services.xserver = {
    enable = true;
    layout = "us";
    xkbVariant = "";
    displayManager.sddm.enable = true;
    windowManager.i3.enable = true; 
    windowManager.xmonad.enable = true;
    windowManager.xmonad.enableContribAndExtras = true;
    windowManager.xmonad.config = builtins.readFile /home/merulox/.config/xmonad/xmonad.hs;
    videoDrivers = ["nvidia"];
 };

  # Define a user account. Don't forget to set a password with 'passwd'.
  users.users.merulox = {
    isNormalUser = true;
    description = "merulox";
    extraGroups = [ "networkmanager" "wheel" "plugdev" "docker" ];
    packages = with pkgs; [];
    uid = 1000;
  };
  # Secrets Provider
  services.passSecretService.enable = true;
  # Gnome Keyring
  services.gnome.gnome-keyring.enable = true;
  # Trusted Users
  nix.settings.trusted-users = [ "root" "merulox" ];
  # Default Shell
  users.defaultUserShell = pkgs.fish;

  # Allow unfree packages
  nixpkgs.config.allowUnfree = true;

  # Environment variables
  environment.sessionVariables = rec {
  QT_QPA_PLATFORMTHEME = "qt5ct";
  #XDG_CURRENT_DESKTOP = "KDE";
  #GTK_USE_PORTAL = "1";
  };

  # Desktop integration portals
   #xdg.portal.extraPortals = [ pkgs.xdg-desktop-portal pkgs.libsForQt5.xdg-desktop-portal-kde ];
    xdg.portal.enable = true;
 

  # Fonts
  fonts.fonts = with pkgs; [
  terminus_font
  carlito
  dejavu_fonts
  ipafont
  kochi-substitute
  ttf_bitstream_vera
  font-awesome
  monocraft
  ];

  fonts.fontconfig.defaultFonts = {
    monospace = [
      "terminus"
      "DejaVu Sans Mono"
      "IPAGothic"
    ];
    sansSerif = [
      "terminus"
      "DejaVu Sans"
      "IPAPGothic"
    ];
    serif = [
      "terminus"
      "DejaVu Serif"
      "IPAPMincho"
    ];
  };
  #  fonts.fontconfig.antialias = false; 



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
    update = "sudo nixos-rebuild switch"; i3config = "nvim ~/.config/i3/config"; zshrc = "nvim ~/.zshrc"; aliases = "nvim ~/.aliases"; bconnect="~/scripts/bconnect"; dconnect = "~/scripts/dconnect"; conf = "cd ~/.config && cd"; rate = "xset r rate 300 25"; chmodall = "sudo chmod 777"; xlayout = "~/.config/i3/xrandr-layout.sh"; nconf = "nvim /etc/nixos/configuration.nix"; ll = "ls -l"; homenix = "nvim /etc/nixos/home.nix"; mb="WINEPREFIX='/home/merulox/MusicBeePrefix' wine '/home/merulox/MusicBeePrefix/drive_c/users/merulox/AppData/Roaming/Microsoft/Windows/Start Menu/Programs/MusicBee/MusicBee.lnk'"; lt = "exa --icons "; ltt = "exa --icons -1"; dotfiles = "cd ~/git/dotfiles && git commit -a -m things && git push"; n = "ncmpcpp"; vim = "nvim";}; 
 
  # Cachix
    nix.settings = {
      substituters = [ "https://ezkea.cachix.org" "https://nix-gaming.cachix.org" ];
      trusted-public-keys = [ "ezkea.cachix.org-1:ioBmUbJTZIKsHmWWXPe1FSFbeVe+afhfgqgTSNd34eI=" "nix-gaming.cachix.org-1:nbjlureqMbRAxR1gJ/f3hxemL9svXaZF/Ees8vCUUs4=" ];
    };
  

  # mpd
  services.mpd = {
  enable = true;
  musicDirectory = "/mnt/data/Audio/Music";
  user = "merulox";
  extraConfig = ''
    audio_output {
      type "pipewire"
      name "mpd"
     }
   '';
  };
  systemd.services.mpd.environment = {
    XDG_RUNTIME_DIR = "/run/user/1000"; 
  };
  
  # Honkers Railway Launcher
  programs.honkers-railway-launcher.enable = true;

  # japanese
  i18n.inputMethod = {
  enabled = "fcitx5";
  fcitx5.addons = with pkgs; [
	fcitx5-mozc
      ];
  };
  # To configure fcitx in the graphical interface, create 2 groups. In the first one, have en+fr where you alternate with a keybinding. In the second, have jap. You will alternate between groups to use jap.
  
  environment.sessionVariables = {
    XMODIFIERS = "@im=fcitx";
    QT_IM_MODULE = "fcitx";
    GTK_IM_MODULE = "fcitx";
    SDL_IM_MODULE = "fcitx";
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
  # services.avahi.openFirewall = true;
 
  # Enable the OpenSSH daemon.
  # services.openssh.enable = true;

  # Open ports in the firewall.
    networking.firewall.enable = true;
    networking.firewall.allowedTCPPorts = [ 8080 ];
    networking.firewall.allowedTCPPortRanges = [ {from = 1714; to = 1764;} ]; #kde connect
    networking.firewall.allowedUDPPorts = [ 8080 ];
    networking.firewall.allowedUDPPortRanges = [ {from = 1714; to = 1764;} ]; #kde connect
  # Or disable the firewall altogether.
  #   networking.firewall.enable = false;


  # This value determines the NixOS release from which the default
  # settings for stateful data, like file locations and database versions
  # on your system were taken. It's perfectly fine and recommended to leave
  # this value at the release version of the first install of this system.
  # Before changing this value read the documentation for this option
  # (e.g. man configuration.nix or on https://nixos.org/nixos/options.html).
  system.stateVersion = "23.05"; # Did you read the comment?
  system.copySystemConfiguration = true;


  # List packages installed in system profile. To search, run:
  # $ nix search wget
  # System Packages
  environment.systemPackages = with pkgs; [
  neovim 
  wget
  git
  i3
  i3status
  i3blocks
  xkb-switch
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
  mpvScripts.mpris
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
  libsForQt5.ffmpegthumbs
  libsForQt5.kdegraphics-thumbnailers
  libsForQt5.qt5.qtimageformats
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
  #katawa-shoujo
  opentabletdriver
  mullvad-vpn
  shutter
  telegram-desktop
  nixos-option
  #osu-lazer
  krita
  elementary-planner
  element-desktop
  nheko
  keepassxc
  psi-plus
  teamspeak5_client
  signal-desktop
  prismlauncher
  jdk8
  librewolf
  speedtest-cli
  spotify
  libsForQt5.kde-cli-tools
  unzip
  #cinny-desktop
  gparted
  protonup-qt
  libsForQt5.kdenlive
  betterdiscordctl
  autokey
  icu
  appimage-run
  #osu-lazer-bin
  #nix-gaming.packages.${pkgs.hostPlatform.system}."osu-lazer-bin"
  vscode
  bottles
  #electron-mail
  #hydroxide - third-party open-source protonmail bridge
  lutris
  protonup-qt
  todoist-electron
  gimp
  sqlite
  picard
  unrar
  monitor
  tauon
  wine-staging
  tmux
  fluent-reader
  libsForQt5.systemsettings
  libsForQt5.qtstyleplugin-kvantum
  copyq
  imagemagick
  exa
  qdirstat
  audacity
  gnome.libgnome-keyring
  openvpn
  networkmanager-openvpn
  protonvpn-cli_2
  ani-cli
  trackma-qt
  ffmpeg
  nicotine-plus
  openvpn
  distrobox  
  nix-prefetch-git
  brave
  qutebrowser
  mkvtoolnix
  adl
  moreutils
  mpd-mpris
  vencord
  webcord-vencord
  viewnior
  libsForQt5.kdeconnect-kde
  freetube
  xclip
  memento
  #glibc
  python311Packages.mpv
  koreader
  cabextract
  uget
  haskellPackages.xmobar
  trayer
  xorg.xev
  logseq
  ];
}
