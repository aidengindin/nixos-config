{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.agindin.hyprland;
  inherit (lib)
    mkIf
    mkEnableOption
    mkOption
    types
    ;
in
{
  imports = [
    ./hyprland/diy.nix
    ./hyprland/dux.nix
  ];

  options.agindin.hyprland = {
    enable = mkEnableOption "Enable hyprland tiling WM";

    shell = mkOption {
      type = types.enum [
        "diy"
        "dux"
      ];
      default = "diy";
      description = ''
        Desktop shell around Hyprland. "diy" is waybar, rofi, swaync, swayosd
        and the hypr* daemons (linux/hyprland/diy.nix); "dux" is Dux Shell, the
        former DankMaterialShell (linux/hyprland/dux.nix).
      '';
    };

    shellLua = mkOption {
      type = types.lines;
      internal = true;
      description = "Shell-specific Hyprland binds, appended to hyprland.lua.";
    };
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
    };

    # fprintd (enabled on this host) makes NixOS inject `auth sufficient
    # pam_fprintd.so` ahead of pam_unix into /etc/pam.d/greetd. Neither
    # greeter's greetd-protocol auth drives the interactive fingerprint prompt,
    # so a correct password is rejected. Force a password-only pam_unix stack.
    security.pam.services = {
      greetd.fprintAuth = false;
      # Unlock the login keyring at greetd login using the entered password, so
      # gnome-keyring's Secret Service is already unlocked for the session. Without
      # this (and services.gnome.gnome-keyring below) there's no Secret Service, so
      # libsecret apps like Claude Desktop / Electron fall back to plaintext ("basic
      # text") credential storage and warn about it.
      greetd.enableGnomeKeyring = true;
    };

    services.gnome.gnome-keyring.enable = true;

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

    # Both shells read the battery via the UPower DBus daemon; the nixpkgs
    # modules don't enable it, so without this the bar shows no battery.
    services.upower.enable = true;

    # KDE Connect: opens TCP/UDP 1714-1764 for phone pairing. Driven over D-Bus
    # by the DankKDEConnect plugin (dux) or kdeconnect-indicator (diy).
    programs.kdeconnect.enable = true;

    home-manager = {
      # DMS writes settings.json/clsettings.json itself; when these become
      # Nix-managed (declarative) the first activation would otherwise abort on
      # the pre-existing unmanaged file. Back it up instead of failing.
      backupFileExtension = "hm-backup";

      users.agindin = {
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

        xdg.configFile."hypr/hyprland.lua".text = builtins.readFile ./hypr/hyprland.lua + cfg.shellLua;

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
      # gnome-keyring stores the encrypted login keyring here; without persistence
      # it'd be recreated empty every boot, discarding saved credentials.
      ".local/share/keyrings"
    ];
  };
}
