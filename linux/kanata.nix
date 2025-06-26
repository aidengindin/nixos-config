{ config, lib, pkgs, ... }:
let
  cfg = config.agindin.kanata;
  inherit (lib) mkIf mkEnableOption mkOption types;
in {
  options.agindin.kanata = {
    enable = mkEnableOption "Whether to enable Kanata";
    keyboardDevices = mkOption {
      type = types.listOf types.str;
      default = [];
      description = "List of input devices to enable Kanata for";
    };
  };

  config = mkIf cfg.enable {
    services.kanata = {
      enable = true;
      keyboards = {
        laptop = {
          devices = cfg.keyboardDevices;
          config = builtins.readFile ./kanata/config.kbd;
        };
      };
    };
  };
}

