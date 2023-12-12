{ config, pkgs, ... }:

{
  config = {
    virtualisation.docker.enable = true;
    virtualisation.arion.backend = "docker";
  };
}

