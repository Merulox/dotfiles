# Edit this configuration file to define what should be installed on
# your system.  Help is available in the configuration.nix(5) man page
# and in the NixOS manual (accessible by running 'nixos-help').
{ config, pkgs, lib, unstable, aagl-gtk-on-nix, nix-gaming, ... }:



{


  # Imports
  imports =
    [ # Include the results of the hardware scan.
      ./hardware-configuration.nix
      ./unstable.nix
      #aagl-gtk-on-nix.module
    ];


  # Flakes
  nix.settings.experimental-features = [ "nix-command" "flakes" ];

  # Insecure packages
  nixpkgs.config.permittedInsecurePackages = [
   "electron-24.8.6"
   "qbittorrent-4.6.4"
   "dotnet-runtime-6.0.36"
   "dotnet-sdk-wrapped-6.0.428"
   "dotnet-sdk-6.0.428"
 ];

  # Opengl
  hardware.graphics = {
    enable = true;
  };
  # Nvidia
  hardware.nvidia = {
    modesetting.enable = true;
    open = false;
    nvidiaSettings = true;
  };
 

  # Reboot / Shutdown
  boot.kernelParams = [
    "reboot=acpi;"
  ];
  boot.kernelModules = [ "uinput" "v4l2loopback" ];
  boot.extraModulePackages = [ config.boot.kernelPackages.v4l2loopback ];
  boot.extraModprobeConfig = ''
    options v4l2loopback devices=1 video_nr=10 card_label="OBS Virtual Camera" exclusive_caps=1
  '';

  # Nvidia drivers
  nixpkgs.config.allowUnfreePredicate = pkg:
    builtins.elem (lib.getName pkg) [
      "nvidia-x11"
      "steam"
      "steam-original"
      "steam-run"
    ];

  # Ollama
  services.ollama.enable = true;

  # ZSH
  programs.zsh.enable = true;
  # Openclaw
  services.openclaw-gateway = {
  enable = true;
  user = "merulox";
  group = "users";
  createUser = false;  # you already exist
  stateDir = "/var/lib/openclaw";

  environmentFiles = [
    "/home/merulox/.secrets/anthropic-api-key.txt"  # should contain ANTHROPIC_API_KEY=sk-...
  ];

  config = {
    gateway = {
      mode = "local";
      auth.token = "pick-any-random-string-here";
    };
    channels.telegram = {
      tokenFile = "/home/merulox/.secrets/telegram-bot-token";
      allowFrom = [ 2069131667 ];  # your Telegram numeric ID from @userinfobot
    };
  };
};
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

  # mpdscribble
  services.mpdscribble = {
  enable = true;
  endpoints = {
    "last.fm" = {
     passwordFile = "/home/merulox/.config/mpdscribble/lastfm-passwordfile";
     username = "merulox";
    };  
    "listenbrainz" = {
     passwordFile = "/home/merulox/.config/mpdscribble/listenbrainz-passwordfile";
     username = "merulox";
    };
  };
  port = 6600;
  host = "localhost";
  };

  # Daily Claude summary at 9pm
  services.cron = {
    enable = true;
    systemCronJobs = [
      "0 21 * * * merulox /home/merulox/scripts/daily-summary.py >> /home/merulox/.claude/daily-summary.log 2>&1"
      "0 6 * * 1 merulox /home/merulox/scripts/lead-gen >> /home/merulox/projects/boreal-leads/lead-gen.log 2>&1"
      "0 8 * * * merulox /home/merulox/scripts/lead-followup-check >> /home/merulox/projects/boreal-leads/followup.log 2>&1"
    ];
  };

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
   jack.enable=true;
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
  virtualisation.docker.enable = true;
  #virtualisation.podman.rootless.enable = true;
   #Mount drive
   fileSystems."/mnt/data" =
    { device = "/dev/sda1";
      fsType = "ntfs-3g"; 
      options = [ "rw" "uid=1000"];
    };
  boot.supportedFilesystems = [ "ntfs" ];

  # Opentabletdriver
  hardware.opentabletdriver.enable = true;
  hardware.opentabletdriver.daemon.enable = true;

  networking = {
    hostName = "navi";
    networkmanager.enable = true;
    wireless.iwd.enable = false;

    firewall = {
      enable = true;
      allowedTCPPorts = [ 80 443 ];
    };
  };
  networking.nameservers = ["45.90.28.97" "45.90.30.97"];
  services.resolved.enable = true;
  #programs.nm-applet.enable = true;
  #networking.wireless.enable = true;  # Enables wireless support via wpa_supplicant.

  # Configure network proxy if necessary
  # networking.proxy.default = "http://user:password@proxy:port/";
  # networking.proxy.noProxy = "127.0.0.1,localhost,internal.domain";


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
    xkb = {
      variant = "";
      layout = "us";
    };
    windowManager.i3.enable = true; 
    windowManager.xmonad.enable = true;
    windowManager.xmonad.enableContribAndExtras = true;
    windowManager.xmonad.config = builtins.readFile ./xmonad.hs;
    videoDrivers = ["nvidia"];
 };
  programs.hyprland.enable = true;
  services.displayManager.sddm.enable = true;
  services.xserver.displayManager.setupCommands = 
  "
  export XDG_MENU_PREFIX=plasma-
  systemctl --user import-environment XDG_MENU_PREFIX
  dbus-update-activation-environment XDG_MENU_PREFIX
  ";
  #environment.plasma5.excludePackages = with pkgs.libsForQt5; [
  #  elisa
  #  gwenview
  #  okular
  #  oxygen
  #  khelpcenter
  #  konsole
  #  print-manager
  #];

  # Define a user account. Don't forget to set a password with 'passwd'.
  users.users.merulox = {
    isNormalUser = true;
    description = "merulox";
    extraGroups = [ "networkmanager" "wheel" "plugdev" "docker" "libvirtd" "input" "plugdev" ];
    packages = with pkgs; [];
    uid = 1000;
    shell = pkgs.zsh;
  };
  # Secrets Provider
  services.passSecretService.enable = true;
  # Gnome Keyring
  services.gnome.gnome-keyring.enable = true;
  # Unlock keyring on SDDM login (fixes Telegram/Chrome session persistence)
  security.pam.services.sddm.enableGnomeKeyring = true;
  # Trusted Users
  nix.settings.trusted-users = [ "root" "merulox" ];
  # Default Shell
  users.defaultUserShell = pkgs.zsh;
  # Piper
  services.ratbagd.enable = true;

  # Allow unfree packages
  nixpkgs.config.allowUnfree = true;

  # Environment variables
  environment.sessionVariables = rec {
  QT_QPA_PLATFORMTHEME = "qt6ct";
  #XDG_CURRENT_DESKTOP = "KDE";
  #GTK_USE_PORTAL = "1";
  };

  # Desktop integration portals
  #xdg.portal.config = [ pkgs.xdg-desktop-portal pkgs.kdePackages.xdg-desktop-portal-kde ];
   xdg.portal = {
    enable = true;
    extraPortals = [
      pkgs.xdg-desktop-portal-gtk
    ];
   };
  #xdg.portal.wlr.enable = true;
  #xdg.portal.xdgOpenUsePortal = true;
#  xdg.portal.config = {
#    common = {
#      default = [
#        "gtk"
#        "kde"
#      ];
#    };
#  };
 

  # Fonts
  fonts.packages = with pkgs; [
  termsyn
  terminus_font
  terminus_font_ttf
  nerd-fonts.jetbrains-mono
  nerd-fonts.terminess-ttf
  carlito
  dejavu_fonts
  ipafont
  kochi-substitute
  ttf_bitstream_vera
  font-awesome
  monocraft
  open-sans
  profont
  hermit
  ];

  fonts.fontconfig.enable = true;
  fonts.fontconfig.defaultFonts = {
    monospace = [
      "hermit"
      "profont"
      "DejaVu Sans Mono"
      "IPAGothic"
    ];
    sansSerif = [
      "hermit"
      "profont"
      "DejaVu Sans"
      "IPAPGothic"
    ];
    serif = [
      "hermit"
      "profont"
      "DejaVu Serif"
      "IPAPMincho"
    ];
  };



  # Programs
  programs.fish.enable = false;

  # Steam
  programs.steam = {
  enable = true;
  remotePlay.openFirewall = true; # Open ports in the firewall for Steam Remote Play
  dedicatedServer.openFirewall = true; # Open ports in the firewall for Source Dedicated Server
  };

  # Shell Aliases
  environment.shellAliases = {
    update = "sudo nixos-rebuild switch"; i3config = "nvim ~/.config/i3/config"; zshrc = "nvim ~/.zshrc"; aliases = "nvim ~/.aliases"; bconnect="~/scripts/bconnect"; dconnect = "~/scripts/dconnect"; conf = "cd ~/.config && cd"; rate = "xset r rate 300 25"; chmodall = "sudo chmod 777"; xlayout = "~/.config/i3/xrandr-layout.sh"; nconf = "nvim /etc/nixos/configuration.nix"; ll = "ls -l"; homenix = "nvim /etc/nixos/home.nix"; mb="WINEPREFIX='/home/merulox/MusicBeePrefix' wine '/home/merulox/MusicBeePrefix/drive_c/users/merulox/AppData/Roaming/Microsoft/Windows/Start Menu/Programs/MusicBee/MusicBee.lnk'"; lt = "exa --icons "; ltt = "exa --icons -1"; dotfiles = "cd ~/git/dotfiles && git commit -a -m things && git push"; n = "ncmpcpp"; vim = "nvim"; xmo = "vim ~/.config/xmonad/xmonad.hs"; xmob = "vim ~/.config/xmobar/xmobar.config"; p2 = "sudo protonvpn c --p2p"; airb = "~/scripts/airb"; aird = "~/scripts/aird";}; 
 
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
      type "pulse"
      name "mpd"
    }
   '';
  };
  #type "pipewire"
  systemd.services.mpd.environment = {
    XDG_RUNTIME_DIR = "/run/user/1000"; 
  };
  
  # virtualisation / kvm / vm
  virtualisation.libvirtd.enable = true;
  programs.dconf.enable = true; # virt-manager requires dconf to remember settings

  # japanese
 # enable = true;
 # type = "fcitx5";
 # fcitx5.addons = with pkgs; [
 #       fcitx5-mozc
 #     ];
 # };
  # To configure fcitx in the graphical interface, create 2 groups. In the first one, have en+fr where you alternate with a keybinding. In the second, have jap. You will alternate between groups to use jap.
  
  environment.sessionVariables = {
    XMODIFIERS = "@im=fcitx";
    QT_IM_MODULE = "fcitx";
    GTK_IM_MODULE = "fcitx";
    SDL_IM_MODULE = "fcitx";
  };
  # KDE mime apps fix
  environment.etc."/xdg/menus/plasma-applications.menu".text = builtins.readFile "${pkgs.kdePackages.plasma-workspace}/etc/xdg/menus/plasma-applications.menu";


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
    #services.flameshot.enable = true;
    #services.dunst.enable = true;


    # Switch controllers
    services.joycond.enable = true;
    services.udev.extraRules = ''
      # Switch Joy-Con (L) - Bluetooth
      KERNEL=="hidraw*", SUBSYSTEM=="hidraw", KERNELS=="0005:057E:2006.*", MODE="0660", TAG+="uaccess"

      # Switch Joy-Con (R) - Bluetooth
      KERNEL=="hidraw*", SUBSYSTEM=="hidraw", KERNELS=="0005:057E:2007.*", MODE="0660", TAG+="uaccess"

      # Switch Pro Controller - USB
      KERNEL=="hidraw*", SUBSYSTEM=="hidraw", ATTRS{idVendor}=="057e", ATTRS{idProduct}=="2009", MODE="0660", TAG+="uaccess"
      SUBSYSTEM=="usb", ATTR{idProduct}=="2009", ATTR{idVendor}=="057e", ENV{ID_INPUT_JOYSTICK}="1", TAG+="uaccess"

      # Switch Pro Controller - Bluetooth
      KERNEL=="hidraw*", SUBSYSTEM=="hidraw", KERNELS=="0005:057E:2009.*", MODE="0660", TAG+="uaccess"

      # Switch Joy-Con Charging Grip - USB
      KERNEL=="hidraw*", SUBSYSTEM=="hidraw", ATTRS{idVendor}=="057e", ATTRS{idProduct}=="200e", MODE="0660", TAG+="uaccess"

      # PDP Rematch wired Controller for Nintendo Switch
      KERNEL=="hidraw*", SUBSYSTEM=="hidraw", ATTRS{idVendor}=="0e6f", ATTRS{idProduct}=="0184", MODE="0660", TAG+="uaccess"
      SUBSYSTEM=="usb", ATTR{idVendor}=="0e6f", ATTR{idProduct}=="0184", ENV{ID_INPUT_JOYSTICK}="1", TAG+="uaccess"

      KERNEL=="uinput", MODE="0660", GROUP="input", OPTIONS+="static_node=uinput"
  '';


  # mime apps
  #xdg.mime.enable = true;
  #xdg.mime.defaultApplications = {
  #  "image/png"="viewnior.desktop";
  #  "image/jpeg"="viewnior.desktop";
  #  "inode/directory"="org.kde.dolphin.desktop";
  #};

  # Printing
  services.printing.enable = true;
  services.printing.drivers = [ pkgs.brlaser pkgs.brgenml1lpr pkgs.brgenml1cupswrapper ];
  services.avahi.enable = true;
  services.avahi.nssmdns4 = true;
  # for a WiFi printer
  # services.avahi.openFirewall = true;
 
  # Enable the OpenSSH daemon.
  # services.openssh.enable = true;

  # Open ports in the firewall.
  #  networking.firewall.allowedTCPPorts = [ 8080 32400 3005 8324 32469 80 443 ];
  #  networking.firewall.allowedTCPPortRanges = [ {from = 1714; to = 1764;} ]; #kde connect
  #  networking.firewall.allowedUDPPorts = [ 8080 32400 1900 5353 32410 32412 32413 32414 ];
  #  networking.firewall.allowedUDPPortRanges = [ {from = 1714; to = 1764;} ]; #kde connect
  # Or disable the firewall altogether.
  #   networking.firewall.enable = false;


  # This value determines the NixOS release from which the default
  # settings for stateful data, like file locations and database versions
  # on your system were taken. It's perfectly fine and recommended to leave
  # this value at the release version of the first install of this system.
  # Before changing this value read the documentation for this option
  # (e.g. man configuration.nix or on https://nixos.org/nixos/options.html).
  system.stateVersion = "23.05"; # Did you read the comment?
  #system.copySystemConfiguration = true;
  #system.autoUpgrade.enable = true; # updates to the latest channels release

  # List packages installed in system profile. To search, run:
  # $ nix search wget
  # System Packages
  # Restic backups to Cloudflare R2
  services.restic.backups.r2 = {
    user = "merulox";
    repository = "s3:https://85fd3bf83c5ee32ce2e3353fa0a58409.r2.cloudflarestorage.com/navi-backup";
    passwordFile = "/home/merulox/.secrets/restic-password";
    environmentFile = "/home/merulox/.secrets/r2-credentials";
    paths = [
      "/home/merulox/.secrets"
      "/home/merulox/projects"
      "/home/merulox/.config/keepassxc"
      "/home/merulox/.config/rclone"
    ];
    exclude = [
      "/home/merulox/.cache"
    ];
    timerConfig = {
      OnCalendar = "daily";
      Persistent = true;
    };
    pruneOpts = [
      "--keep-daily 7"
      "--keep-weekly 4"
      "--keep-monthly 6"
    ];
  };

  environment.systemPackages = with pkgs; [
  restic
  wget
  git
  i3
  i3status
  i3blocks
  xkb-switch
  #vivaldi - moved to unstable
  firefox
  alacritty
  #bitwarden-desktop
  thunderbird
  xdg-desktop-portal
  kdePackages.xdg-desktop-portal-kde
  autotiling
  xfce.thunar
  ntfs3g  
  discord
  slack
  flameshot
  #libsForQt5.qt5ct
  kdePackages.qt6ct
  kdePackages.kdialog
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
  kdePackages.kate
  gnome-icon-theme
  tango-icon-theme
  ayu-theme-gtk
  arc-theme
  arc-kde-theme
  clementine
  strawberry
  wine
  winetricks
  dracula-theme
  neofetch
  ncpamixer
  pavucontrol
  rednotebook
  kdePackages.ark
  #python39Full
  libGL
  gedit
  lxappearance
  #themechanger
  kdePackages.oxygen
  kdePackages.oxygen-icons
  clipmenu
  emojipick
  xdotool
  libsForQt5.qtcurve
  libsForQt5.qtstyleplugins
  variety
  kdePackages.dolphin
  kdePackages.dolphin-plugins
  kdePackages.kio-extras
  kdePackages.ffmpegthumbs
  kdePackages.kdegraphics-thumbnailers
  kdePackages.qtimageformats
  kdePackages.konsole
  kdePackages.kservice
  kdePackages.qtsvg
  blueman
  rxvt-unicode-unwrapped-emoji
  feh
  #nm-tray
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
  # ventoy-full market as insecure, drama rn https://github.com/NixOS/nixpkgs/issues/404663
  zplug
  fish
  fishPlugins.fzf
  zoxide
  betterlockscreen
  artha
  kdePackages.plasma-workspace
  kdePackages.kcalc
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
  #elementary-planner
  element-desktop
  #nheko
  keepassxc
  psi-plus
  signal-desktop
  #prismlauncher -> unstable
  jdk8
  #librewolf
  speedtest-cli
  spotify
  kdePackages.kde-cli-tools
  unzip
  #cinny-desktop
  gparted
  protonup-qt
  kdePackages.kdenlive
  betterdiscordctl
  autokey
  icu
  appimage-run
  #nix-gaming.packages.${pkgs.hostPlatform.system}."osu-lazer-bin"
  vscode
  bottles
  #electron-mail
  hydroxide
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
  kdePackages.systemsettings
  kdePackages.qtstyleplugin-kvantum
  copyq
  imagemagick
  eza
  qdirstat
  audacity
  libgnome-keyring
  openvpn
  networkmanager-openvpn
  protonvpn-gui
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
  #webcord-vencord
  vesktop
  viewnior
  kdePackages.kdeconnect-kde
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
  i3-layout-manager
  htop
  fzf
  ncmpcpp
  mpdscribble
  kdePackages.kfind
  rofi
  xsel
  virt-manager
  hypnotix
  #tor-browser
  ledger-live-desktop
  #hakuneko
  protontricks
  cpu-x
  piper
  #samba4Full # stuff for YosugaNoSora/wine
  #dolphin-emu
  #deadbeef-with-plugins
  #r2modman
  #keymapp switched to unstable
  ueberzug
  youtube-music
  hexchat
  pamix
  onedrive
  catnip #audio visualizer
  plex
  #libgcc
  gcc
  kitty
  libreoffice
  syncthing
  docker
  davinci-resolve
  lmms
  reaper
  yams
  usbmuxd2
  libusbmuxd
  vital
  zoom-us
  gh
  pulseeffects-legacy
  spicetify-cli
  neovim
  vim
  ryubing
  joycond
  joycond-cemuhook
  mesa-demos
  antimicrox
  dolphin-emu
  chromium
  ollama
  scrot
  python3
  nodejs
  nerd-font-patcher
  guvcview
  (wrapOBS { plugins = with obs-studio-plugins; [ obs-backgroundremoval ]; })
  ];
}
