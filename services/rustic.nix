{ config, pkgs, ... }:
let
  cfg = config.agindin.services.rustic;
  inherit (lib) mkIf mkEnableOption;
in
{
  options.agindin.services.rustic = {
    enable = mkEnableOption "rustic";
  };

  config = mkIf cfg.enable {
    environment.systemPackages = with pkgs; [ rustic-rs ];
  };
}

