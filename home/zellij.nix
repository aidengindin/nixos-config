{ config, pkgs, ... }:
{
  config = {
    home-manager.users.agindin.programs.zellij = {
      enable = true;
      enableBashIntegration = true;
    };
  };
}
