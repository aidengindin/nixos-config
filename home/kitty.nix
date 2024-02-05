{ config, lib, pkgs, ... }:
let
  cfg = config.agindin.kitty;
  inherit (lib) mkIf mkEnableOption;
in
{
  options.agindin.kitty = {
    enable = mkEnableOption "kitty";
  };

  config.home-manager.users.agindin = mkIf cfg.enable {
    programs.kitty = mkIf cfg.enable {
      enable = true;
      theme = "Nord";
    };
    home.file."config/kitty/kitty.conf".source = ./kitty/kitty.conf;
  };
}
