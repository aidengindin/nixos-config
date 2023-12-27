{ config, lib, pkgs, ... }:
let
  cfg = config.agindin.alacritty;
  inherit (lib) mkIf mkEnableOption;
in
{
  options.agindin.alacritty = {
    enable = mkEnableOption "alacritty";
  };

  config.home-manager.users.agindin.programs.alacritty = mkIf cfg.enable {
    enable = true;
  };
}
