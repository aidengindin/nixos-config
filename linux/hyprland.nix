{
  config,
  lib,
  pkgs,
  hyprlandFlake,
  dmsFlake,
  unstablePkgs,
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
      hyprshot
      libnotify
      playerctl
      wl-clipboard

      glib
      gsettings-desktop-schemas

      catppuccin-qt5ct
      libsForQt5.qt5ct
      kdePackages.qt6ct
    ];

    programs.hyprland = {
      enable = true;
      withUWSM = true;
      package = hyprlandFlake.packages.${pkgs.system}.hyprland;
      portalPackage = hyprlandFlake.packages.${pkgs.system}.xdg-desktop-portal-hyprland;
    };

    # greetd is enabled and its session command is set by the DMS greeter module
    # (dms.nixosModules.greeter). We only declare the greeter user it runs as.
    users.groups.greeter = { };
    users.users.greeter = {
      isSystemUser = true;
      group = "greeter";
    };
    services.greetd.settings.default_session.user = "greeter";

    programs.dank-material-shell.greeter = {
      enable = true;
      compositor.name = "hyprland";
      quickshell.package = unstablePkgs.quickshell;
      configHome = "/home/agindin";
    };

    # fprintd (enabled on this host) makes NixOS inject `auth sufficient
    # pam_fprintd.so` ahead of pam_unix into /etc/pam.d/greetd. greetd runs that
    # stack for the DankGreeter, whose greetd-protocol auth doesn't drive the
    # interactive fingerprint prompt, so a correct password is rejected. DMS
    # handles fingerprint via its own fprintd path, not this PAM service, so
    # force the greeter (and the DMS lock screen, which falls back to
    # /etc/pam.d/login on NixOS) to a clean password-only pam_unix stack.
    security.pam.services = {
      greetd.fprintAuth = false;
      dankshell.fprintAuth = false;
    };

    xdg.portal = {
      enable = true;
      extraPortals = with pkgs; [
        xdg-desktop-portal-gtk
      ];
    };

    services.libinput = {
      enable = true;
      touchpad = {
        naturalScrolling = true;
      };
    };

    services.logind.settings.Login = mkIf config.agindin.desktop.isLaptop {
      HandleLidSwitch = "suspend";
      HandleLidSwitchExternalPower = "suspend";
      HandleLidSwitchDocked = "ignore";
    };

    programs.dconf.enable = true;
    services.dbus.enable = true;

    # DMS reads the battery via the UPower DBus daemon (Quickshell.Services.UPower).
    # The DMS *NixOS* module would enable this, but we use the home module, so
    # enable it here or the bar shows no battery.
    services.upower.enable = true;

    # TODO: get kde connect working
    # programs.kdeconnect.enable = true;

    home-manager = {
      # DMS writes settings.json/clsettings.json itself; when these become
      # Nix-managed (declarative) the first activation would otherwise abort on
      # the pre-existing unmanaged file. Back it up instead of failing.
      backupFileExtension = "hm-backup";

      users.agindin = {
        imports = [ dmsFlake.homeModules.dank-material-shell ];

        programs.dank-material-shell = {
          enable = true;
          systemd.enable = true;
          quickshell.package = unstablePkgs.quickshell;
          dgop.package = unstablePkgs.dgop;

          # Declarative / read-only: settings.json is snapshotted into the repo
          # and managed by Nix (GUI edits won't persist). Re-snapshot with
          # `cp -L ~/.config/DankMaterialShell/settings.json linux/dms/settings.json`
          # after intentional GUI tuning, then rebuild.
          settings = lib.importJSON ./dms/settings.json;

          session = {
            # DMS only applies monitorWallpapers when perMonitorWallpaper is
            # true; otherwise it uses the (empty) global wallpaperPath.
            perMonitorWallpaper = true;
            wallpaperPath = "/home/agindin/Pictures/wallpapers/nixos.png";
            monitorWallpapers = {
              "eDP-1" = "/home/agindin/Pictures/wallpapers/nixos.png";
              "DP-7" = "/home/agindin/Pictures/wallpapers/stormlight-ultrawide.png";
            };

            # Night mode: 2500K (DMS minimum), auto on a 19:00–05:00 schedule.
            nightModeTemperature = 2500;
            nightModeAutoEnabled = true;
            nightModeAutoMode = "time";
            nightModeStartHour = 19;
            nightModeStartMinute = 0;
            nightModeEndHour = 5;
            nightModeEndMinute = 0;
          };
        };

        # Signal dark mode preference to all apps via xdg-desktop-portal-gtk.
        # Required for Chromium (and others) to report prefers-color-scheme: dark.
        dconf.settings."org/gnome/desktop/interface" = {
          color-scheme = "prefer-dark";
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
          "hypr/hyprland.lua".source = ./hypr/hyprland.lua;

          # volume.sh / brightness.sh removed: volume & display brightness keys
          # now use `dms ipc call audio|brightness …`. Keyboard backlight
          # control was dropped (left permanently off, by choice).
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
      ".config/DankMaterialShell"
      ".local/state/DankMaterialShell"
      ".cache/DankMaterialShell"
    ];

    # DankGreeter has no user dropdown / default-user option; it auto-prefills
    # the last successful username from <cacheDir>/.local/state/memory.json.
    # Persist the greeter cache dir so that memory (and the synced greeter
    # theme/session) survives the impermanent-root wipe on reboot.
    agindin.impermanence.systemDirectories = mkIf config.agindin.impermanence.enable [
      "/var/lib/dms-greeter"
    ];
  };
}
