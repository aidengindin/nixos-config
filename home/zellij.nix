{ config, pkgs, ... }:
{
  config = {
    programs.zellij = {
      enable = true;
      enableBashIntegration = true;
    }
  };
}
