{
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-25.05";
    unstable.url = "github:nixos/nixpkgs/nixos-unstable";

    # managing user environments - both stable & unstable modules
    home-manager = {
      url = "github:nix-community/home-manager/release-25.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    hm-unstable = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "unstable";
    };
    
    nur = {
      url = "github:nix-community/NUR";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    disko = {
      url = "github:nix-community/disko/latest";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    
    impermanence = {
      url = "github:nix-community/impermanence";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nixos-hardware = {
      url = "github:nixos/nixos-hardware/master";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # macos configurations
    darwin = {
      url = "github:lnl7/nix-darwin/nix-darwin-25.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # secrets management
    agenix = {
      url = "github:ryantm/agenix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    catppuccin = {
      url = "github:catppuccin/nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    wallabag-client = {
      url = "github:artur-shaik/wallabag-client";
      inputs.nixpkgs.follows = "nixpkgs";
    };
 };

  outputs = {
    self,
    nixpkgs,
    unstable,
    home-manager,
    hm-unstable,
    nur,
    disko,
    impermanence,
    nixos-hardware,
    darwin,
    agenix,
    catppuccin,
    wallabag-client
    }:
    let

      # standard modules shared by all NixOS systems,
      # with some conditional logic based on whether it tracks stable or unstable
      standardNixosModules = isUnstable: [
        (if isUnstable
          then hm-unstable.nixosModules.home-manager
          else home-manager.nixosModules.home-manager)
        agenix.nixosModules.default
      ];

      # special args for all NixOS systems
      standardSpecialArgs = {
        inherit agenix catppuccin;
        unstablePkgs = unstable.legacyPackages.x86_64-linux;
      };
    in
    {
      nixosConfigurations = {

        # a mini pc home server
        lorien = nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          specialArgs = standardSpecialArgs;
          modules = (standardNixosModules false) ++ [
            ./hosts/lorien
          ];
        };

        # my main laptop
        khazad-dum = nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          specialArgs = standardSpecialArgs;
          modules = (standardNixosModules false) ++ [
            nixos-hardware.nixosModules.framework-amd-ai-300-series
            disko.nixosModules.disko
            impermanence.nixosModules.impermanence
            catppuccin.nixosModules.catppuccin
            catppuccin.homeManagerModules.catppuccin
            ./hosts/khazad-dum
          ];
        };
      };

      darwinConfigurations = {

        # my main laptop
        shadowfax = darwin.lib.darwinSystem {
          system = "aarch64-darwin";
          modules = [
            ./hosts/shadowfax
            home-manager.darwinModules.home-manager
            agenix.darwinModules.default

            # ghostscript fix
            {
              nixpkgs.overlays = [
                (final: prev: {
                  ghostscript = unstable.legacyPackages.aarch64-darwin.ghostscript;
                })
              ];
            }

            ({ config, pkgs, ... }: {
              environment.systemPackages = [ wallabag-client.packages.aarch64-darwin.default ];
            })
          ];
          specialArgs = {
            inherit agenix;
            unstablePkgs = unstable.legacyPackages.aarch64-darwin;
          };
        };
      };
    };
}
