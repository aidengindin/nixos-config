{
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-23.11";
    unstable.url = "github:nixos/nixpkgs/nixos-unstable";
    jovian.url = "github:Jovian-Experiments/Jovian-NixOS/";
    home-manager.url = "github:nix-community/home-manager/release-23.11";
 };

  outputs = { self, nixpkgs, unstable, jovian, home-manager }:
    {
      nixosConfigurations = {
        lorien = nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          modules = [
            ./hosts/lorien
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
    };
}
