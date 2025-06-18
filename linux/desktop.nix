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

    systemd.user.services.lock-on-suspend = {
      description = "Lock screen before suspend";
      before = [ "sleep.target" ];
      wantedBy = [ "sleep.target" ];
      serviceConfig = {
        Type = "forking";
        ExecStart = "${pkgs.hyprlock}/bin/hyprlock";
        TimeoutSec = "infinity";
        Environment = [
          "WAYLAND_DISPLAY=wayland-1"
          "XDG_SESSION_TYPE=wayland"
          "XDG_CURRENT_DESKTOP=Hyprland"
          "XDG_RUNTIME_DIR=/run/user/1000"
        ];
        PAMName = "login";
        
        # Security hardening
        MemoryMax = "256M";
        TasksMax = 50;
        NoNewPrivileges = true;
        # RestrictRealtime = true;
        # RestrictSUIDGUID = true;
        # ProtectSystem = "strict";
        # ProtectHome = false;
        # ReadWritePaths = [
        #   "/dev/input"
        #   "/sys/class/backlight"
        # ];
        PrivateNetwork = true;
        # RestrictNamespaces = true;
        # LockPersonality = true;
        # RestrictAddressFamilies = [ "AF_UNIX" ];
        # SystemCallArchitectures = "native";
        # SystemCallFilter = [
        #   "@system-service"
        #   "~@privileged"
        #   "~@resources"
        #   "~@mount"
        # ];
        # CapabilityBoundingSet = "";
        # AmbientCapabilities = "";
      };
    };

    environment.variables = {
      XCURSOR_THEME = "Catppuccin-Mocha-Dark-Cursors";
      XCURSOR_SIZE = "24";
      GTK_THEME = "catppuccin-mocha-blue";;
    };

    home-manager = {
      users.agindin = {
        gtk = {
          enable = true;
          cursorTheme = {
            name = "Catppuccin-Mocha-Dark-Cursors";
            package = pkgs.catppuccin-cursors.mochaDark;
            size = 24;
          };
          theme = {
            name = "catppuccin-mocha-blue";
            package = pkgs.catppuccin-gtk;
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

        xdg.configFile = {
          "hypr/hyprland.conf".source = ./hypr/hyprland.conf;
          "hypr/hypridle.conf".source = ./hypr/hypridle.conf;
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
      catppuccin-cursors.mochaDark
      hyprpaper
      hyprshot
      iwgtk
      libnotify
      overskride
      rofi-wayland
      swaynotificationcenter
      waybar
      wlogout

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
