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
    settings = {
      font = {
        normal = {
          family = "Hasklug Nerd Font";
          style = "Regular";
        };
        # bold = {
        #   family = "Hasklug Nerd Font";
        #   style = "Bold";
        # };
        # italic = {
        #   family = "Hasklug Nerd Font";
        #   style = "Italic";
        # };
        # bold_italic = {
        #   family = "Hasklug Nerd Font";
        #   style = "Bold Italic";
        # };
      };
    };
  };
}
