{ config, lib, pkgs, ... }:
let
  cfg = config.agindin.firefox;
  inherit (lib) mkIf mkEnableOption;
in
{
  options.agindin.firefox = {
    enable = mkEnableOption "firefox";
  };

  config = mkIf cfg.enable {
    home-manager.users.agindin.programs.firefox = {
      enable = true;
    };
  };
}
