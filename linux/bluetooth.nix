{ config, lib, pkgs, ... }:
let
  cfg = config.agindin.bluetooth;
  inherit (lib) mkIf mkEnableOption;
in {
  options.agindin.bluetooth = {
    enable = mkEnableOption "Whether to enable bluetooth-related configuration";
  };

  config = mkIf cfg.enable {
    hardware.bluetooth = {
      enable = true;
    };
  };
}

