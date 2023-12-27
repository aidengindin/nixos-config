{ config, lib, pkgs, ... }:
let
  cfg = config.agindin.kitty;
  inherit (lib) mkIf mkEnableOption;
in
{
  options.agindin.kitty = {
    enable = mkEnableOption "kitty";
  };

  config.home-manager.users.agindin.programs.kitty = mkIf cfg.enable {
    enable = true;
    font = {
      name = "Hasklug Nerd Font";
      size = 12;
    };
  };
}
