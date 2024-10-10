{ config, pkgs, ...}:
let
  baseconfig = { allowUnfree = true; };
  unstable = import <nixos-unstable> { config = baseconfig; };
in {
  environment.systemPackages = with pkgs; [
     unstable.calibre
     unstable.rclone
     #unstable.floorp
     #unstable.quodlibet
     unstable.lunar-client
     unstable.protonvpn-gui
     unstable.osu-lazer-bin
     unstable.ani-cli
     unstable.vivaldi
     unstable.r2modman
     #unstable.animdl
     unstable.adl
     unstable.keymapp
  ];
}
