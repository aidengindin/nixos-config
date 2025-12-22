{
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-25.11";
    unstable.url = "github:nixos/nixpkgs/nixos-unstable";

    # managing user environments - both stable & unstable modules
    home-manager = {
      url = "github:nix-community/home-manager/release-25.11";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    hm-unstable = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "unstable";
    };

    disko = {
      url = "github:nix-community/disko/latest";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    
    impermanence.url = "github:nix-community/impermanence";

    nixos-hardware.url = "github:nixos/nixos-hardware/master";

    # secrets management
    agenix = {
      url = "github:ryantm/agenix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    zwift = {
      url = "github:netbrain/zwift";
      inputs.nixpkgs.follows = "unstable";
    };
 };

  outputs = {
    self,
    nixpkgs,
    unstable,
    home-manager,
    hm-unstable,
    disko,
    impermanence,
    nixos-hardware,
    agenix,
    zwift
  }:
    let

      # standard modules shared by all NixOS systems,
      # with some conditional logic based on whether it tracks stable or unstable
      standardNixosModules = isUnstable: [
        (if isUnstable
          then hm-unstable.nixosModules.home-manager
          else home-manager.nixosModules.home-manager)
        agenix.nixosModules.default
        zwift.nixosModules.default
      ];

      # special args for all NixOS systems
      standardSpecialArgs = {
        inherit agenix;
        unstablePkgs = import unstable {
          system = "x86_64-linux";
          config.allowUnfree = true;
        };
      };
    in {
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
            ./hosts/khazad-dum
          ];
        };
      };
    };
}
