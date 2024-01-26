{
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-23.11";
    unstable.url = "github:nixos/nixpkgs/nixos-unstable";
    jovian = {
      url = "github:Jovian-Experiments/Jovian-NixOS/";
      inputs.nixpkgs.follows = "unstable";
    };
    home-manager.url = "github:nix-community/home-manager/release-23.11";
    darwin = {
      url = "github:lnl7/nix-darwin";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    emacs-overlay = {
      url = "github:nix-community/emacs-overlay/"; 
      inputs.nixpkgs.follows = "nixpkgs";
    };
    arion = {
      url = "github:hercules-ci/arion";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    agenix = {
      url = "github:ryantm/agenix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
 };

  outputs = { self, nixpkgs, unstable, jovian, home-manager, darwin, emacs-overlay, arion, agenix }:
    let
      emacsModule = ({ config, ... }: {
        nixpkgs.overlays = [
	        emacs-overlay.overlay
	      ];
      });
      standardNixosModules = [
        home-manager.nixosModules.home-manager
        agenix.nixosModules.default
      ];
    in
    {
      nixosConfigurations = {
        lorien = nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          modules = standardNixosModules ++ [
            ./hosts/lorien
            arion.nixosModules.arion
          ];
        };

        weathertop = nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          modules = standardNixosModules ++ [
            ./hosts/weathertop
            jovian.nixosModules.default
          ];
        };
      };

      darwinConfigurations = {
        shadowfax = darwin.lib.darwinSystem {
          system = "aarch64-darwin";
          modules = [
            ./hosts/shadowfax
            home-manager.darwinModules.home-manager
            emacsModule
          ];
        };
      };
    };
}

