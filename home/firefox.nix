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
    programs.firefox = {
      enable = true;
    };
  };
}
