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

    colmena.url = "github:zhaofengli/colmena";

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

    jovian = {
      url = "github:jovian-experiments/jovian-nixos";
      inputs.nixpkgs.follows = "unstable";
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
    colmena,
    disko,
    impermanence,
    nixos-hardware,
    agenix,
    jovian,
    zwift
  }:
    let
      inherit (nixpkgs.lib) mapAttrs;

      # standard modules shared by all NixOS systems,
      # with some conditional logic based on whether it tracks stable or unstable
      standardNixosModules = isUnstable: [
        (if isUnstable
          then hm-unstable.nixosModules.home-manager
          else home-manager.nixosModules.home-manager)
        agenix.nixosModules.default
        zwift.nixosModules.default
        impermanence.nixosModules.impermanence
      ];

      # special args for all NixOS systems
      standardSpecialArgs = {
        inherit agenix colmena;
        unstablePkgs = import unstable {
          system = "x86_64-linux";
          config.allowUnfree = true;
        };
      };

      nodeDefaults = {
        deployment.targetUser = "nixos-deploy";
      };

      nodes = {
        lorien = {
          isUnstable = false;
          tags = [ "server" ];
          allowLocalDeployment = true;
          modules = [
            ./hosts/lorien
          ];
        };
        khazad-dum = {
          isUnstable = false;
          tags = [ "laptop" ];
          allowLocalDeployment = true;
          modules = [
            nixos-hardware.nixosModules.framework-amd-ai-300-series
            disko.nixosModules.disko
            ./hosts/khazad-dum
          ];
        };
        weathertop = {
          isUnstable = true;
          tags = [ "portable" ];
          allowLocalDeployment = false;
          modules = [
            jovian.nixosModules.default
          ];
        };
      };
    in {
      colmenaHive = colmena.lib.makeHive self.outputs.colmena;

      colmena = {
        meta = {
          nixpkgs = import nixpkgs {
            system = "x86_64-linux";
            overlays = [];
          };
          specialArgs = standardSpecialArgs;
        };

        defaults = nodeDefaults;
      } // (mapAttrs (name: node: { ... }: {
        imports = (standardNixosModules node.isUnstable) ++ node.modules;
        deployment = {
          allowLocalDeployment = node.allowLocalDeployment;
          tags = node.tags;
        };
      } // (if node.isUnstable then {
        _module.args.pkgs = import unstable {
          system = "x86_64-linux";
          config.allowUnfree = true;
        };
      } else {})) nodes);

      nixosConfigurations = mapAttrs (name: node:
        let
          pkgsSource = if node.isUnstable
            then unstable
            else nixpkgs;
        in pkgsSource.lib.nixosSystem {
          system = "x86_64-linux";
          specialArgs = standardSpecialArgs;
          modules = (standardNixosModules node.isUnstable) ++ node.modules;
        }
      ) nodes;
    };
}
