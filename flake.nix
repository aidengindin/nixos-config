let
  stableVersion = "23.11";
  unstableVersion = "24.05";
in
{
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-${stableVersion}";
    unstable.url = "github:nixos/nixpkgs/nixos-unstable";
    jovian = {
      url = "github:Jovian-Experiments/Jovian-NixOS/";
      inputs.nixpkgs.follows = "unstable";
    };
    # home-manager.url = "github:nix-community/home-manager/release-23.11";
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    hm-unstable = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "unstable";
    };
    darwin = {
      url = "github:lnl7/nix-darwin";
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

  outputs = { self, nixpkgs, unstable, jovian, home-manager, hm-unstable, darwin, arion, agenix }:
    let
      standardNixosModules = isUnstable: [
        if isUnstable
          then hm-unstable.nixosModules.home-manager
          else home-manager.nixosModules.home-manager
        agenix.nixosModules.default
        ({ config, ... }: {
          home.stateVersion = if isUnstable
            then unstableVersion
            else stableVersion;
        });
      ];
      standardSpecialArgs = {
        inherit agenix;
      };
    in
    {
      nixosConfigurations = {
        lorien = nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          specialArgs = standardSpecialArgs;
          modules = (standardNixosModules false) ++ [
            ./hosts/lorien
            arion.nixosModules.arion
          ];
        };

        weathertop = unstable.lib.nixosSystem {
          system = "x86_64-linux";
          specialArgs = standardSpecialArgs;
          modules = (standardNixosModules true) ++ [
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
          ];
        };
      };
    };
}

