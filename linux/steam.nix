{ config, lib, pkgs, ... }:
let
  cfg = config.agindin.steam;
  inherit (lib) mkIf mkEnableOption;
in {
  options.agindin.steam = {
    enable = mkEnableOption "steam";
  };

  config = mkIf cfg.enable {
    programs.steam = {
      enable = true;
    };
  };
}

