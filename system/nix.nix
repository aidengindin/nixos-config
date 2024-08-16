{ config, lib, pkgs, ... }:
{
  config = {
    nixpkgs.config.allowUnfree = true;

    nix = {
      package = pkgs.nixFlakes;
      extraOptions = ''
          experimental-features = nix-command flakes
        '';
        optimise = {
          automatic = true;
          # interval = {
          #   Weekday = 0;
          #   Hour = 1;
          #   Minute = 0;
          # };
          dates = [ "weekly" ];
        };
        gc = {
          automatic = true;
          # interval = {
          #   Weekday = 0;
          #   Hour = 0;
          #   Minute = 0;
          # };
          dates = "weekly";
          options = "--delete-older-than 30d";
        };
    };
  }
}
