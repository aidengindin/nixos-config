{ config, lib, ... }:
let
  cfg = config.agindin.gnome;
  inherit (lib) mkEnableOption mkIf;
in {
  options.agindin.gnome = {
    enable = mkEnableOption "Whether to enable GNOME desktop environment.";
    gdm.enable = mkEnableOption "Whether to enable GDM display manager.";
  };

  config = mkIf cfg.enable {
    assertions = [
      {
        assertion = (! config.agindin.hyprland.enable);
        message = "Only one desktop environment can be configured.";
      }
    ];

    agindin.desktop.enable = true;

    services.displayManager.gdm.enable = mkIf cfg.gdm.enable true;
    services.desktopManager.gnome.enable = true;

    services.gnome = {
      core-developer-tools.enable = false;
      games.enable = false;
    };

    agindin.impermanence.userDirectories = mkIf config.agindin.impermanence.enable [
      ".local/share/gnome-shell"
      ".config/dconf"
    ];
  };
}

