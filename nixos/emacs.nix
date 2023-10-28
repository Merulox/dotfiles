{ config, pkgs, lib, ... }:
  let 
  doom-emacs = pkgs.callPackage (builtins.fetchTarball {
    url = https://github.com/nix-community/nix-doom-emacs/archive/master.tar.gz; 
  }) {
    doomPrivateDir = ./doom.d;  # Directory containing your config.el init.el
                                # and packages.el files
  };
  
  in
{
  home.packages = [ doom-emacs ];

  # ./doom.d should contain the following three files: config.el, init.el and packages.el. If you don't already have an existing doom-emacs configuration, you can use the contents of test/doom.d as a template.

  #home.file.".emacs.d/init.el".text = ''
  #    (load "default.el")
  #'';
}
