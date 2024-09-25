
{ config, lib, pkgs, ... }:

{
  config = {
    virtualisation.oci-containers.backend = "docker";
    virtualisation.containers.enable = true;
    virtualisation.docker.autoPrune.enable = true;
  };
}