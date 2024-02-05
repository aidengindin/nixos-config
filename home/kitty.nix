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
    theme = "Nord";
    settings = {
      cursor_blink_interval = 0;
      enable_audio_bell = "no";
      tab_bar_style = "powerline";

      # confirm closing a window/tab only when a command is running
      confirm_os_window_close = -1;

      font_family = "Hasklug Nerd Font Mono";
      bold_font = "Hasklug Nerd Font Mono Bold";
      italic_font = "Hasklug Nerd Font Mono Italic";
      bold_italic_font = "Hasklug Nerd Font Mono Bold Italic";
      font_size = 12;
    };
  };
}
