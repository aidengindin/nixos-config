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
    services.hypridle.enable = true;

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

    home-manager = {
      users.agindin = {
        gtk = {
          enable = true;
          # cursorTheme = {
          #   name = "Catppuccin-Mocha-Dark-Cursors";
          #   package = pkgs.catppuccin-cursors.mochaDark;
          #   size = 24;
          # };
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
          style = {
            name = "catppuccin-mocha-blue";
            package = pkgs.catppuccin-qt5ct;
          };
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

        xdg.configFile = {
          "hypr/hyprland.conf".source = ./hypr/hyprland.conf;
          "hypr/hypridle.conf".source = ./hypr/hypridle.conf;
          "hypr/hyprpaper.conf".source = ./hypr/hyprpaper.conf;
          "hypr/hyprlock.conf".source = ./hypr/hyprlock.conf;
          "hypr/mocha.conf".source = ./hypr/mocha.conf;

          "swaync/config.json".source = ./swaync/config.json;
          "swaync/style.css".source = ./swaync/style.css;

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

          "wlogout/style.css".source = ./wlogout/style.css;
          "wlogout/lock.svg".source = ./wlogout/lock.svg;
          "wlogout/suspend.svg".source = ./wlogout/suspend.svg;
          "wlogout/hibernate.svg".source = ./wlogout/logout.svg;
          "wlogout/shutdown.svg".source = ./wlogout/shutdown.svg;
          "wlogout/reboot.svg".source = ./wlogout/reboot.svg;
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
      # catppuccin-cursors.mochaDark
      hyprpaper
      hyprshot
      hyprsunset
      iwgtk
      libnotify
      overskride
      rofi-wayland
      swaynotificationcenter
      waybar
      wlogout
      wl-clipboard

      glib
      gsettings-desktop-schemas

      anki
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
    ];
  };
}
