{ config, lib, ... }:
let
  cfg = config.agindin.gnome;
  inherit (lib) mkEnableOption mkIf;
in
{
  options.agindin.gnome = {
    enable = mkEnableOption "Whether to enable GNOME desktop environment.";
    gdm.enable = mkEnableOption "Whether to enable GDM display manager.";
  };

  config = mkIf cfg.enable {
    assertions = [
      {
        assertion = (!config.agindin.hyprland.enable);
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

    home-manager.users.agindin.dconf = {
      enable = true;
      settings = {
        "org/gnome/desktop/interface" = {
          color-scheme = "prefer-dark";
          enable-hot-corners = false;
          show-battery-percentage = true;
        };
        "org/gnome/desktop/session" = {
          idle-delay = "uint32 900";
        };
        "org/gnome/desktop/screensaver" = {
          lock-enable = true;
        };
        "org/gnome/mutter" = {
          edge-tiling = true;
        };
        "org/gnome/settings-daemon/plugins/power" = {
          idle-dim = true;
        };
      };
    };
  };
}
