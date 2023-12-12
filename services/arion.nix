{ config, pkgs, ... }:

{
  config = {
    # environment.systemPackages = with pkgs; [ arion ];
    modules = with pkgs; [ arion.nixosModules.arion ];
    virtualisation.docker.enable = true;
    virtualisation.arion.backend = "docker";
  };
}
