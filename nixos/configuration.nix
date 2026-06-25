# Edit this configuration file to define what should be installed on
# your system.  Help is available in the configuration.nix(5) man page
# and in the NixOS manual (accessible by running 'nixos-help').
{ config, pkgs, lib, unstable, aagl-gtk-on-nix, nix-gaming, ... }:

let
  goldfish = pkgs.stdenvNoCC.mkDerivation rec {
    pname = "goldfish";
    version = "0.1.0";

    src = pkgs.fetchurl {
      url = "https://github.com/sameoldlab/goldfish/releases/download/v${version}/gf-x86_64-unknown-linux-gnu";
      hash = "sha256-NmPYlHZBSPMcVZs9HQV3IEW1Pnutaj69AnuX89PaG1A=";
    };

    dontUnpack = true;

    installPhase = ''
      runHook preInstall
      install -Dm755 "$src" "$out/bin/gf"
      runHook postInstall
    '';

    meta = {
      description = "IPC fuzzy file finder";
      homepage = "https://github.com/sameoldlab/goldfish";
      license = lib.licenses.mpl20;
      platforms = [ "x86_64-linux" ];
      mainProgram = "gf";
    };
  };
in
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
  hardware.nvidia-container-toolkit.enable = true;
 

  # Reboot / Shutdown
  boot.kernelParams = [
    "reboot=acpi"
    "usb-storage.quirks=152d:a583:u"
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
  services.ollama = {
  enable = false;
  package = pkgs.ollama-cuda;
    loadModels = [
      "qwen2.5-coder:7b"
      "qwen2.5-coder:3b"
      "hermes3:8b"
    ];
  };

  # YubiKey — udev rules for device recognition (hardware not required to configure)
  services.udev.packages = with pkgs; [ yubikey-personalization ];
  services.pcscd.enable = true; # smartcard daemon required for YubiKey

  # OpenSnitch — network monitor (Linux equivalent of Little Snitch)
  services.opensnitch.enable = true;

  programs.appimage = {
	enable = true;
	binfmt = true;
  };
  # ZSH
  programs.zsh.enable = true;
  # Openclaw
  services.openclaw-gateway = {
  enable = false;
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
      enabled = true;
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
      # Upward push — nightly ceiling-finder, runs after daily summary
      "30 21 * * * merulox /home/merulox/scripts/upward-push >> /tmp/upward-push.log 2>&1"
      "0 6 * * 1 merulox /home/merulox/scripts/lead-gen >> /home/merulox/projects/boreal-leads/lead-gen.log 2>&1"
      "0 8 * * * merulox /home/merulox/scripts/lead-followup-check >> /home/merulox/projects/boreal-leads/followup.log 2>&1"
      # Vault intelligence loop
      "0 20 * * 0 merulox /home/merulox/scripts/drift-report >> /tmp/drift-report.log 2>&1"
      "0 21 * * 3 merulox /home/merulox/scripts/vault-challenge >> /tmp/vault-challenge.log 2>&1"
      "0 10 1 * * merulox /home/merulox/scripts/vault-ideas >> /tmp/vault-ideas.log 2>&1"
      # Task system
      "1 8 * * * merulox /home/merulox/scripts/task-push >> /tmp/task-push.log 2>&1"
      "*/15 * * * * merulox /home/merulox/scripts/task-inbox >> /tmp/task-inbox.log 2>&1"
      # Feedback loops
      "30 8 * * * merulox /home/merulox/scripts/signals-updater >> /tmp/signals-updater.log 2>&1"
      "0 6 * * 2 merulox /home/merulox/scripts/soumission-scraper >> /home/merulox/projects/boreal-leads/soumission-scraper.log 2>&1"
      # Knowledge intake
      "0 7 * * * merulox /home/merulox/scripts/channel-watcher >> /tmp/channel-watcher.log 2>&1"
      "30 7 * * * merulox /home/merulox/scripts/newsletter-pipeline >> /tmp/newsletter-pipeline.log 2>&1"
      "0 7 * * 1,4 merulox /home/merulox/scripts/brain-rss >> /tmp/brain-rss.log 2>&1"
      "0 9 * * 0 merulox /home/merulox/scripts/ingest-queue >> /tmp/ingest-queue.log 2>&1"
      # Knowledge self-improvement loop — weekly Wed 8am
      # Disabled by Genesis freeze audit: autonomous API/agent loop.
      # "0 8 * * 3 merulox /home/merulox/scripts/brain-loop >> /tmp/brain-loop.log 2>&1"
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
   wireplumber.enable=true;
  };
  # bitwig
  
  security.pam.loginLimits = [
    { domain = "@audio"; type = "hard"; item = "rtprio"; value = "99"; }
    { domain = "@audio"; type = "soft"; item = "rtprio"; value = "99"; }
    { domain = "@audio"; type = "hard"; item = "memlock"; value = "unlimited"; }
    { domain = "@audio"; type = "soft"; item = "memlock"; value = "unlimited"; }
  ];
  environment.pathsToLink = [ "/share/lsp-plugins" "/lib/vst" "/lib/vst3" "/lib/clap" ];


  # bluetooth 
  hardware.bluetooth.enable = true;
  # zsa
  hardware.keyboard.zsa.enable = true;
  # Bootloader.
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
  # podman
  virtualisation.podman.enable = true; # for distrobox
  virtualisation.docker = {
  enable = true;
  };
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
    networkmanager = {
      enable = true;
      # Delegate DNS to systemd-resolved so NextDNS nameservers are actually used
      dns = "systemd-resolved";
    };
    wireless.iwd.enable = false;

    firewall = {
      enable = true;
      allowedTCPPorts = [ 80 443 ];
    };
  };
  networking.nameservers = ["45.90.28.97" "45.90.30.97"];
  services.resolved = {
    enable = true;
    # Use NextDNS as primary, fall back to nothing (no Google/Cloudflare leakage)
    settings.Resolve.FallbackDNS = [];
  };
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
    extraGroups = [ "audio" "networkmanager" "wheel" "docker" "libvirtd" "input" "plugdev" ];
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
    remotePlay.openFirewall = true;
    dedicatedServer.openFirewall = true;
  };
  hardware.steam-hardware.enable = true; # udev rules for Steam Input (controller remapping via uinput)

  # Shell Aliases
  environment.shellAliases = {
    update = "sudo nixos-rebuild switch"; i3config = "nvim ~/.config/i3/config"; zshrc = "nvim ~/.zshrc"; aliases = "nvim ~/.aliases"; bconnect="~/scripts/bconnect"; dconnect = "~/scripts/dconnect"; conf = "cd ~/.config && cd"; rate = "xset r rate 300 25"; chmodall = "sudo chmod 777"; xlayout = "~/.config/i3/xrandr-layout.sh"; nconf = "nvim /etc/nixos/configuration.nix"; ll = "ls -l"; homenix = "nvim /etc/nixos/home.nix"; mb="WINEPREFIX='/home/merulox/MusicBeePrefix' wine '/home/merulox/MusicBeePrefix/drive_c/users/merulox/AppData/Roaming/Microsoft/Windows/Start Menu/Programs/MusicBee/MusicBee.lnk'"; lt = "exa --icons "; ltt = "exa --icons -1"; dotfiles = "cd ~/git/dotfiles && git commit -a -m things && git push"; n = "ncmpcpp"; vim = "nvim"; xmo = "vim ~/.config/xmonad/xmonad.hs"; xmob = "vim ~/.config/xmobar/xmobar.config"; p2 = "sudo protonvpn c --p2p"; airb = "~/scripts/airb"; aird = "~/scripts/aird"; realm = "realm-session";}; 
 
  # Cachix
    nix.settings = {
      substituters = [ "https://ezkea.cachix.org" "https://nix-gaming.cachix.org" ];
      trusted-public-keys = [ "ezkea.cachix.org-1:ioBmUbJTZIKsHmWWXPe1FSFbeVe+afhfgqgTSNd34eI=" "nix-gaming.cachix.org-1:nbjlureqMbRAxR1gJ/f3hxemL9svXaZF/Ees8vCUUs4=" ];
    };
  

  # mpd
  services.mpd = {
  enable = true;
  settings.music_directory = "/mnt/data/Audio/Music";
  user = "merulox";
  };
  #type "pipewire"
  systemd.services.mpd.environment = {
    XDG_RUNTIME_DIR = "/run/user/1000";
  };

  programs.nix-ld.enable = true;
  # Genesis — persistent agent daemon + Telegram bridge
  systemd.services.genesis-bridge = {
    description = "Genesis Telegram bridge (@meruloxsgenesisbot)";
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    wantedBy = [ "multi-user.target" ];
    unitConfig = {
      StartLimitIntervalSec = "300";
      StartLimitBurst = 5;
    };
    serviceConfig = {
      User = "merulox";
      Group = "users";
      ExecStart = "${pkgs.python3}/bin/python3 /home/merulox/projects/genesis/telegram-bridge.py";
      Environment = "PATH=${pkgs.python3}/bin:/run/current-system/sw/bin:/run/wrappers/bin";
      Restart = "on-failure";
      RestartSec = "10s";
      StandardOutput = "journal";
      StandardError = "journal";
    };
  };

  systemd.services.genesis = {
    description = "Genesis agent daemon";
    after = [ "network-online.target" "genesis-bridge.service" ];
    wants = [ "network-online.target" "genesis-bridge.service" ];
    wantedBy = [ "multi-user.target" ];
    unitConfig = {
      StartLimitIntervalSec = "300";
      StartLimitBurst = 3;
    };
    serviceConfig = {
      User = "merulox";
      Group = "users";
      ExecStart = "${pkgs.python3}/bin/python3 /home/merulox/projects/genesis/daemon.py";
      Environment = "PATH=${pkgs.python3}/bin:/run/current-system/sw/bin:/run/wrappers/bin:/home/merulox/scripts";
      Restart = "on-failure";
      RestartSec = "30s";
      StandardOutput = "journal";
      StandardError = "journal";
    };
  };

  # sms-inbox daemon — polls Twilio every 30s, classifies inbound replies, triggers reply-agent
  systemd.services.sms-inbox = {
    enable = false;
    description = "Boréal SMS inbox poller";
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    serviceConfig = {
      User = "merulox";
      Group = "users";
      ExecStart = "${pkgs.python3}/bin/python3 /home/merulox/scripts/sms-inbox --daemon";
      Environment = "PATH=${pkgs.python3}/bin:/run/current-system/sw/bin:/run/wrappers/bin";
      Restart = "on-failure";
      RestartSec = "15s";
      StandardOutput = "journal";
      StandardError = "journal";
    };
  };
  
  # virtualisation / kvm / vm
  virtualisation.libvirtd.enable = true;
  programs.dconf.enable = true; # virt-manager requires dconf to remember settings

  # japanese / french accents input
  i18n.inputMethod = {
    enable = true;
    type = "fcitx5";
    fcitx5.addons = with pkgs; [
      fcitx5-mozc
      fcitx5-gtk
    ];
  };
  # To configure fcitx in the graphical interface, create 2 groups. In the first one, have en+fr where you alternate with a keybinding. In the second, have jap. You will alternate between groups to use jap.
  
  environment.sessionVariables = {
    XMODIFIERS = "@im=fcitx";
    QT_IM_MODULE = "fcitx";
    GTK_IM_MODULE = "fcitx";
    SDL_IM_MODULE = "fcitx";
    OPENROUTER_API_KEY = "~/.secrets/openrouter-api-key.txt";
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
  r2modman
  restic
  # Security tools
  yubikey-manager          # YubiKey CLI management
  yubikey-personalization  # YubiKey config tool
  opensnitch-ui            # OpenSnitch GUI (network monitor)
  # Voice transcription for openclaw Telegram bot
  whisper-cpp              # Whisper C++ — fast local speech-to-text
  cloudflared
  goldfish
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
  thunar
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
  zathura
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
  fastfetch
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
  jq
  curl 
  wireguard-tools
  openresolv
  xkill
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
  #mullvad-vpn
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
  proton-vpn
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
  python3Packages.mpv
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
  tor-browser
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
  pear-desktop
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
  (python3.withPackages (ps: with ps; [ textual rich ]))
  nodejs
  nerd-font-patcher
  guvcview
  (wrapOBS { plugins = with obs-studio-plugins; [ obs-backgroundremoval ]; })
  codex
  zed-editor
  code-cursor
  cursor-cli
  browsers
  bitwig-studio
  qjackctl
  jackmix
  ghostty
  wezterm
  warp-terminal
  zellij
  z-library-desktop
  opencode
  opencode-claude-auth
  tree
  openai-whisper
  qpwgraph
  whisperx
  mission-center
  vicinae
  ];
}
