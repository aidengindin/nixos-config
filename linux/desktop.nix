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

    # Enable sound
    security.rtkit.enable = true;
    services.pipewire = {
      enable = true;
      alsa.enable = true;
      alsa.support32Bit = true;
      pulse.enable = true;
    };

    services.logind = {
      lidSwitch = "suspend";
      lidSwitchExternalPower = "suspend";
      lidSwitchDocked = "ignore";
    };

    programs.dconf.enable = true;
    services.dbus.enable = true;

    programs.kdeconnect.enable = true;

    home-manager = {
      users.agindin = {
        gtk = {
          enable = true;
          theme = {
            name = "catppuccin-mocha-blue-compact";
            package = pkgs.catppuccin-gtk.override {
              variant = "mocha";
              accents = [ "blue" ];
              size = "compact";
            };
          };
          font = {
            name = "Noto Sans";
            package = pkgs.noto-fonts;
            size = 12;
          };
        };

        qt = {
          enable = true;
          platformTheme.name = "qtct";
        };

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
            notification-icon-size =  48;
            notification-body-image-height =  100;
            notification-body-image-width =  200;
            timeout =  2;
            timeout-low =  2;
            timeout-critical =  0;
            notification-window-width =  300;
            keyboard-shortcuts =  true;
            image-visibility =  "when-available";
            transition-time =  200;
            hide-on-clear =  true;
            hide-on-action =  true;
            widgets =  [
              "title"
              "dnd"
              "notifications"
            ];
            widget-config =  {
              title =  {
                text =  "Notifications";
                clear-all-button =  true;
                button-text =  "Clear All";
              };
              dnd =  {
                text =  "Do Not Disturb";
              };
              mpris =  {
                image-size =  96;
                blur =  true;
              };
            };
          };
        };

        xdg.configFile = let
          catppuccinQtColors = "${pkgs.catppuccin-qt5ct}/share/qt5ct/colors";
        in {
          "hypr/hyprland.conf".source = ./hypr/hyprland.conf;
          "hypr/hypridle.conf".source = ./hypr/hypridle.conf;
          "hypr/hyprpaper.conf".source = ./hypr/hyprpaper.conf;
          "hypr/hyprlock.conf".source = ./hypr/hyprlock.conf;
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

          "rofi/config.rasi".source = ./rofi/config.rasi;
          "rofi/catppuccin-mocha.rasi".source = ./rofi/catppuccin-mocha.rasi;
          "rofi/catppuccin-default.rasi".source = ./rofi/catppuccin-default.rasi;

          "qt5ct/colors" = {
            source = catppuccinQtColors;
            recursive = true;
          };
          "qt6ct/colors" = {
            source = catppuccinQtColors;
            recursive = true;
          };
        };

        home.file = {
          "Pictures/wallpapers/nixos.png".source = ./wallpapers/nixos.png;
        };
      };
    };

    fonts.packages = with pkgs; [
      nerd-fonts.hasklug
    ];

    # Packages that should be installed on all desktop systems
    environment.systemPackages = with pkgs; [
      brightnessctl
      cliphist
      hyprpaper
      hyprshot
      hyprsunset
      libnotify
      playerctl
      rofi-wayland
      swaynotificationcenter
      waybar
      wl-clipboard
      wttrbar

      glib
      gsettings-desktop-schemas

      catppuccin-qt5ct
      libsForQt5.qt5ct
      kdePackages.qt6ct

      anki
      bitwarden
      kitty
      ungoogled-chromium
      zoom-us
    ];
  };
}
