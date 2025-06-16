{ config, pkgs, lib, ... }:
let
  cfg = config.agindin.desktop;
  inherit (lib) mkEnableOption mkIf;
in
{
  options.agindin.desktop = {
    enable = mkEnableOption "desktop";
  };

  config = mkIf cfg.enable {
    programs.hyprland = {
      enable = true;
      withUWSM = true;
    };

    services.greetd = {
      enable = true;
      settings = rec {
        default_session = {
          command = "Hyprland &> /dev/null";
          user = config.user.name;
        };
        initial_session = default_session;
      };
    };
    
    xdg.portal = {
      enable = true;
      extraPortals = with pkgs; [
        xdg-desktop-portal-gtk
        xdg-desktop-portal-hyprland
      ];
    };

    programs.hyprlock.enable = true;
    programs.hypridle.enable = true;

    # Enable sound
    sound.enable = true;
    hardware.pulseaudio.enable = false;
    security.rtkit.enable = true;
    services.pipewire = {
      enable = true;
      alsa.enable = true;
      alsa.support32Bit = true;
      pulse.enable = true;
    };

    home-manager = {
      users.agindin.dconf = {
        enable = true;
        settings = {
          "org/gnome/shell" = {
            enabled-extensions = [
              "gsconnect@andyholmes.github.io"
            ];
          };
          "org/gnome/desktop/interface" = {
            color-scheme = "prefer-dark";
            enable-hot-corners = false;
            show-battery-percentage = true;
          };
          "org/gnome/desktop/session" = {
            idle-delay = "uint32 900";
          };
          "org/gnome/desktop/screensaver" = {
            lock-enabled = true;
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

    # Packages that should be installed on all desktop systems
    environment.systemPackages = with pkgs; [
      hyprshot
      iwgtk
      overskride
      rofi-wayland
      waybar

      bitwarden
      discord
      element-desktop
      kitty
      spotify
      thunderbird
      ungoogled-chromium
      vscodium
      whatsapp-for-linux
      zoom-us

      # gnomeExtensions.gsconnect
    ];
  };
}
