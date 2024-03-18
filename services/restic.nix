{ config, lib, pkgs, ... }:
let
  cfg = config.agindin.services.rustic;
  inherit (lib) mkIf mkEnableOption;
in
{
  options.agindin.services.restic = {
    enable = mkEnableOption "restic";
  };

  config = mkIf cfg.enable {
  };
}

