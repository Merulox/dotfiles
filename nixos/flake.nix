{
  description = "Minimal NixOS flake with Home Manager";
  inputs = {

    # nixpkgs
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";
    nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixos-unstable";
    # home-manager
    home-manager.url = "github:nix-community/home-manager/release-25.11";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";
    # gtk-on-nix
    aagl-gtk-on-nix.url = "github:ezKEa/aagl-gtk-on-nix";
    aagl-gtk-on-nix.inputs.nixpkgs.follows = "nixpkgs";
    # nix-gaming
    nix-gaming.url = "github:fufexan/nix-gaming";
    nix-gaming.inputs.nixpkgs.follows = "nixpkgs";
    # openclaw 
    nix-openclaw.url = "github:openclaw/nix-openclaw";

  };
  outputs = { self, nixpkgs, nixpkgs-unstable, home-manager, aagl-gtk-on-nix, nix-gaming, nix-openclaw, ... }:
  let
    system = "x86_64-linux";
    hostname = "navi";
    unstable = import nixpkgs-unstable { inherit system; config.allowUnfree = true; };
  in
  {
    nixosConfigurations = {
      "${hostname}" = nixpkgs.lib.nixosSystem {
        inherit system;
        specialArgs = { inherit unstable aagl-gtk-on-nix nix-gaming; };
        modules = [
          ./configuration.nix
          home-manager.nixosModules.home-manager
          {
            home-manager.useGlobalPkgs = true;
            home-manager.useUserPackages = true;
            home-manager.users.merulox = import ./home.nix;
          }
            nix-openclaw.nixosModules.openclaw-gateway
            ({ ... }: {
             nixpkgs.overlays = [
               (final: prev: {
                 openclaw-gateway = (import nixpkgs-unstable {
                   system = "x86_64-linux";
                   config.allowUnfree = true;
                   overlays = [ nix-openclaw.overlays.default ];
                 }).openclaw-gateway;
               })
             ];
})
        ];
      };
    };
  };
}
