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

  outputs =
    {
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
      zwift,
    }:
    let
      inherit (nixpkgs.lib) mapAttrs;

      pkgsConfig = {
        system = "x86_64-linux";
        config.allowUnfree = true;
      };

      # pre-configured pkgs instances
      stablePkgs = import nixpkgs pkgsConfig;

      unstablePkgs = import unstable pkgsConfig;

      # Standard modules shared by all NixOS systems,
      # with some conditional logic based on whether it tracks stable or unstable.
      # Note that not all modules are used by all systems,
      # but since their options are included in shared modules, they must be imported here.
      standardNixosModules = isUnstable: [
        (
          if isUnstable then hm-unstable.nixosModules.home-manager else home-manager.nixosModules.home-manager
        )
        agenix.nixosModules.default
        zwift.nixosModules.default
        impermanence.nixosModules.impermanence
        disko.nixosModules.disko
        jovian.nixosModules.default
      ];

      # special args for all NixOS systems
      standardSpecialArgs = {
        inherit agenix colmena unstablePkgs;
      };

      nodeDefaults = {
        deployment.targetUser = "nixos-deploy";
      };

      nodes = {
        lorien = {
          isUnstable = false;
          tags = [
            "server"
            "onprem"
          ];
          allowLocalDeployment = false;
          modules = [ ./hosts/lorien ];
        };

        osgiliath = {
          isUnstable = false;
          tags = [
            "server"
            "onprem"
          ];
          allowLocalDeployment = true;
          modules = [ ./hosts/osgiliath ];
        };

        khazad-dum = {
          isUnstable = false;
          tags = [
            "laptop"
            "mobile"
          ];
          allowLocalDeployment = true;
          modules = [
            nixos-hardware.nixosModules.framework-amd-ai-300-series
            ./hosts/khazad-dum
          ];
        };

        weathertop = {
          isUnstable = true;
          tags = [
            "gaming"
            "mobile"
          ];
          allowLocalDeployment = false;
          modules = [ ./hosts/weathertop ];
        };
      };
    in
    {
      colmenaHive = colmena.lib.makeHive self.outputs.colmena;

      colmena = {
        meta = {
          nixpkgs = stablePkgs;
          nodeNixpkgs = mapAttrs (name: node: if node.isUnstable then unstablePkgs else stablePkgs) nodes;
          specialArgs = standardSpecialArgs;
        };

        defaults = nodeDefaults;
      }
      // (mapAttrs (
        name: node:
        { ... }:
        {
          imports = (standardNixosModules node.isUnstable) ++ node.modules;
          deployment = {
            allowLocalDeployment = node.allowLocalDeployment;
            tags = node.tags;
          };
        }
      ) nodes);

      nixosConfigurations =
        (mapAttrs (
          name: node:
          let
            pkgsSource = if node.isUnstable then unstable else nixpkgs;
            pkgs = if node.isUnstable then unstablePkgs else stablePkgs;
          in
          pkgsSource.lib.nixosSystem {
            system = "x86_64-linux";
            specialArgs = standardSpecialArgs;
            modules =
              (standardNixosModules node.isUnstable)
              ++ node.modules
              ++ [
                { nixpkgs.pkgs = pkgs; }
              ];
          }
        ) nodes)
        // {

          # Custom minimal ISO for unattended nixos-anywhere installations
          # Includes bcachefs support for systems that use it
          iso = nixpkgs.lib.nixosSystem {
            system = "x86_64-linux";
            modules = [
              "${nixpkgs}/nixos/modules/installer/cd-dvd/installation-cd-minimal.nix"
              (
                { pkgs, ... }:
                {
                  # Use latest kernel for bcachefs support
                  boot.kernelPackages = pkgs.linuxPackages_latest;
                  boot.supportedFilesystems = {
                    bcachefs = true;
                    zfs = nixpkgs.lib.mkForce false;
                  };

                  services.openssh = {
                    enable = true;
                    settings.PermitRootLogin = "yes";
                  };

                  # Set a simple password for ssh login
                  users.users.root.password = "password";

                  networking.networkmanager.enable = true;

                  environment.systemPackages = with pkgs; [ smartmontools e2fsprogs ];
                }
              )
            ];
          };
        };

      packages.x86_64-linux.iso = self.nixosConfigurations.iso.config.system.build.isoImage;
    };
}
