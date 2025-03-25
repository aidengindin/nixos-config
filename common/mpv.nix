{ config, lib, pkgs, ... }:
let
  cfg = config.agindin.mpv;
  inherit (lib) mkIf mkEnableOption;
in
{
  options.agindin.mpv = {
    enable = mkEnableOption "mpv";
  };

  config = mkIf cfg.enable {
    home-manager.users.agindin.programs.mpv = {
      enable = true;
      scripts = with pkgs.mpvScripts; [
        sponsorblock
      ];
      bindings = {
        "j" = "seek -5";
        ";" = "seek 5";
        "k" = "add volume -2";
        "l" = "add volume 2";
      };
    };
  };
}

