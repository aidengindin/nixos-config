{ config, lib, pkgs, ... }:
let
  cfg = config.agindin.services.blocky;
  inherit (lib) mkIf mkEnableOption mkOption types;
in
{
  options.agindin.services.ollama = {
    enable = mkEnableOption "ollama";
  };

  config = mkIf cfg.enable {
    services.ollama = {
      enable = true;
    };
  };
}
