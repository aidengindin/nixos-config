{ config, lib, pkgs, ... }:
let
  cfg = config.agindin.zwift;
  inherit (lib) mkIf mkEnableOption;
in {
  options.agindin.zwift = {
    enable = mkEnableOption "zwift";
  };

  config = mkIf cfg.enable {
    programs.zwift = {
      enable = true;
      containerTool = "docker";
      wineExperimentalWayland = true;
    };
  };
}

