{ config, lib, pkgs, ... }:
{
  config.nix = {
    optimise = {
      enable = true;
      dates = [ "weekly" ];
    };
    gc = {
      automatic = true;
      dates = [ "weekly" ];
      options = "--delete-older-than 30d";
    };
  };
}

