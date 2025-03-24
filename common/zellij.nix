{ config, lib, pkgs, ... }:
let
  cfg = config.agindin.zellij;
  inherit (lib) mkIf mkEnableOption;
in
{
  options.agindin.zellij = {
    enable = mkEnableOption "zellij";
  };

  config = mkIf cfg.enable {
    home-manager.users.agindin.programs.zellij = {
      enable = true;
      enableBashIntegration = true;
      settings = {
        theme = "nord";
      };
    };
  };
}
