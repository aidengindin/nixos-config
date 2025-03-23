{ config, lib, pkgs, ... }:
let
  cfg = config.agindin.yabai;
  inherit (lib) mkIf mkEnableOption;
in
{
  options.agindin.yabai = {
    enable = mkEnableOption "yabai";
  };

  config = mkIf cfg.enable {
    services = {
      yabai = {
        enable = true;
        enableScriptingAddition = true;
        config = {
          layout = "bsp";

          top_padding = 15;
          bottom_padding = 15;
          left_padding = 15;
          right_padding = 15;
          window_gap = 15;

          mouse_modifier = "alt";

          focus_follows_mouse = "autoraise";
          mouse_follows_focus = "off";

          # external_bar = "all:20:0";
        };
        extraConfig = ''
          yabai -m rule --add app="^System Settings$" manage=off
        '';
      };
      skhd = {
        enable = true;
        skhdConfig = ''
          # Focus windows
          alt - j : yabai -m window --focus west
          alt - k : yabai -m window --focus south
          alt - l : yabai -m window --focus north
          alt - ; : yabai -m window --focus east

          # Move windows
          alt + shift - j : yabai -m window --swap west
          alt + shift - k : yabai -m window --swap south
          alt + shift - l : yabai -m window --swap north
          alt + shift - ; : yabai -m window --swap east

          # Resize windows
          alt + cmd - h : yabai -m window --resize left:-20:0 || yabai -m window --resize right:-20:0
          alt + cmd - j : yabai -m window --resize bottom:0:20 || yabai -m window --resize top:0:20
          alt + cmd - k : yabai -m window --resize top:0:-20 || yabai -m window --resize bottom:0:-20
          alt + cmd - l : yabai -m window --resize right:20:0 || yabai -m window --resize left:20:0

          alt - b : yabai -m space --balance

          alt - t : yabai -m window --toggle float
          alt - f : yabai -m window --toggle zoom-fullscreen

          # Space navigation
          alt - 1 : yabai -m space --focus 1
          alt - 2 : yabai -m space --focus 2
          alt - 3 : yabai -m space --focus 3
          alt - 4 : yabai -m space --focus 4
          alt - 5 : yabai -m space --focus 5
          alt - 6 : yabai -m space --focus 6
          alt - 7 : yabai -m space --focus 7
          alt - 8 : yabai -m space --focus 8

          # Move window to space
          alt + shift - 1 : yabai -m window --space 1
          alt + shift - 2 : yabai -m window --space 2
          alt + shift - 3 : yabai -m window --space 3
          alt + shift - 4 : yabai -m window --space 4
          alt + shift - 5 : yabai -m window --space 5
          alt + shift - 6 : yabai -m window --space 6
          alt + shift - 7 : yabai -m window --space 7
          alt + shift - 8 : yabai -m window --space 8
        '';
      };
      sketchybar = {
        enable = false;
      };
    };
  };
}
