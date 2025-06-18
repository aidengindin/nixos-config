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
      config = {
        background-color = "#1e1e2e";
        osd-back-color = "#11111b";
        osd-border-color = "#11111b";
        osd-color = "#cdd6f4";
        osd-shadow-color = "#1e1e2e";
      };
      scriptOpts = {
        stats = {
          border_color = "251818";
          font_color = "f4d6cd";
          plot_bg_border_color = "fab489";
          plot_bg_color = "251818";
          plot_color = "fab489";
        };
        uosc = {
          color = "foreground=89b4fa,foreground_text=313244,background=1e1e2e,background_text=cdd6f4,curtain=181825,success=a6e3a1,error=f38ba8";
        };
      };
    };
  };
}
