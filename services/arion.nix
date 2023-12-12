{ config, pkgs, ... }:

{
  config = {
    # environment.systemPackages = with pkgs; [ arion ];
    virtualisation.docker.enable = true;
    virtualisation.arion.backend = "docker";
  };
}
