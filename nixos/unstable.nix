{ config, pkgs, unstable, ...}:
{
  environment.systemPackages = with pkgs; [
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
     unstable.prismlauncher
     unstable.rmpc
     unstable.claude-code
  ];
}
