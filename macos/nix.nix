{ config, lib, pkgs, ... }:
{
  config = {
    services.nix-daemon.enable = true;
    nix = {
      optimise = {
        automatic = true;
        interval = {
          Weekday = 0;
          Hour = 1;
          Minute = 0;
        };
      };
      gc = {
        automatic = true;
        interval = {
          Weekday = 0;
          Hour = 1;
          Minute = 0;
        };
        options = "--delete-older-than 30d";
      };
    };
  };
}
