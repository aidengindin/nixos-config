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
    # sound.enable = true; # This option is deprecated
    hardware.pulseaudio.enable = false;
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

    home-manager = {
      users.agindin = {
        xdg.configFile = {
          "hypr/hyprland.conf".source = ./hypr/hyprland.conf;
          "waybar/config".source = ./waybar/config;
          "hypr/hypridle.conf".source = ./hypr/hypridle.conf;
          "swaync/config.json".source = ./swaync/config.json;
          "swaync/style.css".source = ./swaync/style.css;
          "hypr/scripts/volume.sh" = {
            source = ./hypr/scripts/volume.sh;
            executable = true;
          };
          "hypr/scripts/brightness.sh" = {
            source = ./hypr/scripts/brightness.sh;
            executable = true;
          };
        };
      };
    };

    # Packages that should be installed on all desktop systems
    environment.systemPackages = with pkgs; [
      brightnessctl
      hyprshot
      iwgtk
      libnotify
      overskride
      rofi-wayland
      swaynotificationcenter
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
    ];
  };
}
