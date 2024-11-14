{ config, lib, pkgs, ... }:
{
  config = {
    home-manager.users.agindin = {
      programs.direnv = {
        enable = true;
        # silent = true;
        enableBashIntegration = true;
        nix-direnv.enable = true;
      };
    };
  };
}