{ config, lib, pkgs, ... }:
{
  config = {
    nix = {
      optimise = {
        automatic = true;
        dates = [ "weekly" ];
      };
      gc = {
        automatic = true;
        dates = "weekly";
        options = "--delete-older-than 30d";
      };
    };
    system.rebuild.enableNg = true;
  };
}

