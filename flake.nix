{
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-23.11";
    unstable.url = "github:nixos/nixpkgs/nixos-unstable";
    jovian.url = "github:Jovian-Experiments/Jovian-NixOS/";
    home-manager.url = "github:nix-community/home-manager/release-23.11";
    darwin.url = "github:lnl7/nix-darwin";
    darwin.inputs.nixpkgs.follows = "nixpkgs";

 };

  outputs = { self, nixpkgs, unstable, jovian, home-manager, darwin }:
    {
      nixosConfigurations = {
        lorien = nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          modules = [
            ./hosts/lorien
            home-manager.nixosModules.home-manager
          ];
        };
        weathertop = nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          modules = [
            ./hosts/weathertop
            jovian.nixosModules.default
            home-manager.nixosModules.home-manager
          ];
        };
      };

      darwinConfigurations = {
        shadowfax = darwin.lib.darwinSystem {
          system = "aarch64-darwin";
          modules = [
            ./hosts/shadowfax
            home-manager.nixosModules.home-manager
          ];
        };
      };
    };
}
