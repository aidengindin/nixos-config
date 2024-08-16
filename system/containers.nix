
{ config, lib, pkgs, ... }:

{
  config = {
    virtualisation.oci-containers.backend = "docker";
  };
}