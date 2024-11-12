{ config, lib, pkgs, ... }:
{
  config = {
    home-manager.users.agindin = {
      programs.zoxide = {
        enable = true;
        enableBashIntegration = true;
      };
    };
  };
}