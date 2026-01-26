{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.agindin.hyprland;
  inherit (lib) mkIf mkEnableOption;
in
{
  options.agindin.hyprland = {
    enable = mkEnableOption "Enable hyprland tiling WM";
  };

  config = mkIf cfg.enable {
    assertions = [
      {
        assertion = (!config.agindin.gnome.enable);
        message = "Only one desktop environment can be configured.";
      }
    ];

    agindin.desktop.enable = true;

    environment.systemPackages = with pkgs; [
      brightnessctl
      cliphist
      hyprpaper
      hyprshot
      hyprsunset
      libnotify
      playerctl
      rofi
      swaynotificationcenter
      waybar
      wl-clipboard
      wttrbar

      glib
      gsettings-desktop-schemas

      catppuccin-qt5ct
      libsForQt5.qt5ct
      kdePackages.qt6ct
    ];

    programs.hyprland = {
      enable = true;
      withUWSM = true;
    };

    services.greetd = {
      enable = true;
      settings = rec {
        default_session = {
          command = "Hyprland &> /dev/null";
          user = "agindin";
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

    services.libinput = {
      enable = true;
      touchpad = {
        naturalScrolling = true;
      };
    };

    programs.hyprlock.enable = true;

    services.logind.settings.Login = mkIf config.agindin.desktop.isLaptop {
      HandleLidSwitch = "suspend";
      HandleLidSwitchExternalPower = "suspend";
      HandleLidSwitchDocked = "ignore";
    };

    programs.dconf.enable = true;
    services.dbus.enable = true;

    # TODO: get kde connect working
    # programs.kdeconnect.enable = true;

    home-manager = {
      users.agindin = {
        home.pointerCursor = {
          enable = true;
          name = "catppuccin-mocha-dark-cursors";
          package = pkgs.catppuccin-cursors.mochaDark;
          size = 24;
          hyprcursor = {
            enable = true;
            size = 24;
          };
          gtk.enable = true;
          x11.enable = true;
        };

        services.swaync = {
          enable = true;
          style = builtins.readFile ./swaync/style.css;
          settings = {
            notification-icon-size = 48;
            notification-body-image-height = 100;
            notification-body-image-width = 200;
            timeout = 2;
            timeout-low = 2;
            timeout-critical = 0;
            notification-window-width = 300;
            keyboard-shortcuts = true;
            image-visibility = "when-available";
            transition-time = 200;
            hide-on-clear = true;
            hide-on-action = true;
            widgets = [
              "title"
              "dnd"
              "notifications"
            ];
            widget-config = {
              title = {
                text = "Notifications";
                clear-all-button = true;
                button-text = "Clear All";
              };
              dnd = {
                text = "Do Not Disturb";
              };
              mpris = {
                image-size = 96;
                blur = true;
              };
            };
          };
        };

        xdg.configFile = {
          "hypr/hyprland.conf".source = ./hypr/hyprland.conf;
          "hypr/hypridle.conf".source = ./hypr/hypridle.conf;
          "hypr/hyprpaper.conf".source = ./hypr/hyprpaper.conf;
          "hypr/hyprlock.conf".source = ./hypr/hyprlock.conf;
          "hypr/hyprsunset.conf".source = ./hypr/hyprsunset.conf;
          "hypr/mocha.conf".source = ./hypr/mocha.conf;

          "waybar/config".source = ./waybar/config;
          "waybar/style.css".source = ./waybar/style.css;

          "hypr/scripts/volume.sh" = {
            source = ./hypr/scripts/volume.sh;
            executable = true;
          };
          "hypr/scripts/brightness.sh" = {
            source = ./hypr/scripts/brightness.sh;
            executable = true;
          };
          "hypr/scripts/bluetooth.sh" = {
            source = ./hypr/scripts/bluetooth.sh;
            executable = true;
          };
          "hypr/scripts/audio.sh" = {
            source = ./hypr/scripts/audio.sh;
            executable = true;
          };
          "hypr/scripts/wifi.sh" = {
            source = ./hypr/scripts/wifi.sh;
            executable = true;
          };

          "rofi/config.rasi".source = ./rofi/config.rasi;
          "rofi/catppuccin-mocha.rasi".source = ./rofi/catppuccin-mocha.rasi;
          "rofi/catppuccin-default.rasi".source = ./rofi/catppuccin-default.rasi;
        };

        # TODO: fix udiskie
        services.udiskie = {
          enable = true;
          settings = {
            program_options = {
              tray = false;
            };
            device_config = [
              {
                id_vendor = "RPI";
                id_model = "RP2";
                options = [
                  "uid=1000"
                  "gid=100"
                  "umask=0022"
                ];
              }
            ];
          };
        };
      };
    };

    agindin.impermanence.userDirectories = mkIf config.agindin.impermanence.enable [
      ".config/kdeconnect"
    ];
  };
}
