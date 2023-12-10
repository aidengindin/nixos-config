{ config, pkgs, lib, ... }:
let
  cfg = config.agindin.desktop;
  inherit (lib) mkOption mkEnableOption mkIf types;
in
{
  options.agindin.desktop = {
    enable = mkEnableOption "desktop";
  };

  config = mkIf cfg.enable {
    services.xserver.desktopManager.gnome.enable = true;
  };
}

