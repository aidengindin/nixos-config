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
      family = "Hasklug Nerd Font";
      size = 12;
    };
    theme = "Nord";
    settings = {
      cursor_blink_interval = 0;
      enable_audio_bell = "no";
      tab_bar_style = "powerline";

      # confirm closing a window/tab only when a command is running
      confirm_os_window_close = -1;
    };
  };
}
