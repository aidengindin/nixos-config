{
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-24.05";
    unstable.url = "github:nixos/nixpkgs/nixos-unstable";

    # packages & configurations for steam deck
    jovian = {
      url = "github:Jovian-Experiments/Jovian-NixOS/";
      inputs.nixpkgs.follows = "unstable";
    };

    # managing user environments - both stable & unstable modules
    home-manager = {
      url = "github:nix-community/home-manager/release-24.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    hm-unstable = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "unstable";
    };

    # macos configurations
    darwin = {
      url = "github:lnl7/nix-darwin";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # managing docker containers
    arion = {
      url = "github:hercules-ci/arion";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # secrets management
    agenix = {
      url = "github:ryantm/agenix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
 };

  outputs = { self, nixpkgs, unstable, jovian, home-manager, hm-unstable, darwin, arion, agenix }:
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
        inherit agenix;
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
            arion.nixosModules.arion
          ];
        };

        # my steam deck
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

        # my main laptop
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
