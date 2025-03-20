{ config, lib, pkgs, ... }:
{
  config = {
    nixpkgs.config.allowUnfree = true;

    nix = {
      package = pkgs.nixVersions.stable;
      extraOptions = ''
          experimental-features = nix-command flakes
        '';
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
  };
}
