{
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-23.11";
    jovian.url = "github:Jovian-Experiments/Jovian-NixOS/";
  };

  outputs = { self, nixpkgs, jovian }:
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
          ];
        };
      };
    };
}
