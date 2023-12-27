{ config, lib, pkgs, ... }:
let
  cfg = config.agindin.eza;
  inherit (lib) mkIf mkEnableOption;
in
{
  options.agindin.eza = {
    enable = mkEnableOption "eza";
  };

  config.home-manager.users.agindin.programs.eza = mkIf cfg.enable {
    enable = true;
    enableAliases = true;
    git = true;
    icons = true;
  };
}
