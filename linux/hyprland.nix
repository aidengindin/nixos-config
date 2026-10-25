{
  config,
  lib,
  pkgs,
  unstablePkgs,
  dmsPluginSources,
  ...
}:
let
  cfg = config.agindin.hyprland;
  inherit (lib) mkIf mkEnableOption;

  jsonFormat = pkgs.formats.json { };

  # Plugin sources are `flake = false` inputs (see flake.nix), locked in
  # flake.lock and bumped by the updater under its 7-day cooldown. Two of them
  # are monorepos; point those plugins' `src` at the relevant subdirectory.
  src = dmsPluginSources;

  # Third-party DMS plugins. Each attr name MUST equal the plugin's manifest
  # `id` (from its plugin.json): programs.dux-shell installs the source to
  # /etc/xdg/quickshell/dms-plugins/<name> (a system plugin dir DMS scans) AND
  # plugin_settings.json below is keyed by <name>, and DMS matches enabled-state
  # by manifest id — a mismatch installs the plugin but never enables it.
  # Bar-widget plugins also need a layout entry in dms/settings.json
  # (barConfigs); launcher plugins are reached by their trigger string.
  dmsPlugins = {
    # Launchers (spotlight triggers): ":e" emoji, "=" calc, "nix" pkgs.
    emojiLauncher.src = src.emojiLauncher;
    calculator.src = src.calculator;
    nixPackageRunner.src = src.nixPackageRunner;

    # Bar widgets (placed in dms/settings.json barConfigs).
    amdGpuMonitorRevive.src = src.amdGpuMonitor;
    ambientSound.src = src.ambientSound;
    hyprlandSubmapIndicator.src = "${src.nderscore}/HyprlandSubmapIndicator";
    dankKDEConnect.src = "${src.avenge}/DankKDEConnect";
    dankPomodoroTimer.src = "${src.avenge}/DankPomodoroTimer";
  };

  # ~/.config/DankMaterialShell/plugin_settings.json: one { enabled = true; }
  # entry per plugin (what the DMS flake's home module generated).
  dmsPluginSettings = lib.mapAttrs (_: _: { enabled = true; }) dmsPlugins;

  dmsSession = {
    # DMS only applies monitorWallpapers when perMonitorWallpaper is
    # true; otherwise it uses the (empty) global wallpaperPath.
    perMonitorWallpaper = true;
    wallpaperPath = "/home/agindin/Pictures/wallpapers/nixos.png";
    monitorWallpapers = {
      "eDP-1" = "/home/agindin/Pictures/wallpapers/nixos.png";
      "DP-7" = "/home/agindin/Pictures/wallpapers/stormlight-ultrawide.png";
    };

    # Night mode: 2500K (DMS minimum), auto on a 19:00–05:00 schedule.
    # nightModeEnabled is the master switch — with it off, DMS never
    # evaluates the schedule (DisplayService.evaluateNightMode returns
    # early). With master + auto both on, the gamma daemon holds 6500K
    # (neutral) during the day, so this doesn't tint daytime hours.
    nightModeEnabled = true;
    nightModeTemperature = 2500;
    nightModeAutoEnabled = true;
    nightModeAutoMode = "time";
    nightModeStartHour = 19;
    nightModeStartMinute = 0;
    nightModeEndHour = 5;
    nightModeEndMinute = 0;
  };
in
{
  # The stable (26.05) nixpkgs DMS modules target dms-shell 1.4.x, where the
  # greeter was still bundled in the dms-shell package. The unstable package we
  # run (1.6.x) split the greeter into its own `dms-greeter` package, so use
  # unstable's modules (and packages) instead of stable's. Unstable has since
  # renamed DMS to Dux Shell (modules, options and packages are now dux-*), but
  # the runtime names (dms-greeter user, /var/lib/dms-greeter, dms-plugins dir,
  # dms user unit, dms-greeter PAM service) are unchanged.
  disabledModules = [
    "programs/wayland/dms-shell.nix"
    "services/display-managers/dms-greeter.nix"
  ];
  imports = [
    "${unstablePkgs.path}/nixos/modules/programs/wayland/dux-shell.nix"
    "${unstablePkgs.path}/nixos/modules/services/display-managers/dux-greeter.nix"
  ];

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

      # Runtime dependency of the amdGpuMonitorRevive DMS plugin. (mpv, needed
      # by the ambientSound plugin, is already installed via common/mpv.nix.)
      amdgpu_top

      # DMS calendar-events backend. The old DMS home module installed this
      # (enableCalendarEvents); the nixpkgs module expects it installed separately.
      khal

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

    # The nixpkgs DMS shell module installs the dms package + quickshell
    # system-wide, runs dms as a systemd user unit (shipped by the package), and
    # installs plugins to /etc/xdg/quickshell/dms-plugins. It has no equivalent of
    # the old home-manager module's `settings`/`session`/plugin_settings.json; those
    # are written below via home-manager files.
    programs.dux-shell = {
      enable = true;
      # Dux Shell 2.0 draws M3 Expressive decorations (cookie/sunny/flower
      # blobs on the weather cards, scalloped badges, the wind "arrow" blob).
      # Its only off switch is a zero corner radius, which also squares every
      # corner. Instead, alias the decorative catalog entries to plain shapes
      # at build time; everything that draws one goes through this catalog.
      # The QML is copied into the Go binary during preBuild (make sync-shell).
      package = unstablePkgs.dux-shell.overrideAttrs (old: {
        preBuild = ''
          # quickshell/DCommon is a symlink into this submodule.
          chmod -R u+w ../dux-qml-common
          cat >>../dux-qml-common/DCommon/Widgets/MaterialShapes.js <<'EOF'

          for (const kind of Object.keys(catalog)) {
              if (!["circle", "square", "oval", "pill", "semiCircle", "dankLogo"].includes(kind))
                  catalog[kind] = kind === "slanted" ? catalog.square : catalog.circle;
          }
          EOF

          # The default ("expressive") lock-screen password field swaps its
          # icon between morphing shapes on every keystroke. Keep the field
          # style but always take the plain-icon path.
          chmod -R u+w ../quickshell
          substituteInPlace ../quickshell/Modules/Lock/Widgets/LockAuthWidget.qml \
            --replace-fail 'readonly property bool morph: style === "expressive"' \
                           'readonly property bool morph: false'
        ''
        + old.preBuild;
      });
      quickshell.package = unstablePkgs.quickshell;
      plugins = dmsPlugins;
    };

    # greetd is enabled and its session command is set by the nixpkgs DMS greeter
    # module, which also creates the dms-greeter user/group (and the
    # /var/lib/dms-greeter home) greetd runs the greeter as.
    services.displayManager.dux-greeter = {
      enable = true;
      package = unstablePkgs.dux-greeter;
      compositor.name = "hyprland";
      quickshell.package = unstablePkgs.quickshell;
      configHome = "/home/agindin";
    };

    # /var/lib/dms-greeter is persisted, and the flake greeter this replaced ran
    # as a different user (`greeter`). The module's pre-start only chowns
    # non-hidden files (`chown … *`), so its leftover `.cache` stayed owned by
    # the old user and the new greeter died on `mkdir .cache/dms-greeter-shell:
    # permission denied`, leaving no login screen. Own the whole tree right
    # before each launch, as root, whatever state a previous generation left.
    systemd.services.greetd.preStart = lib.mkAfter ''
      ${pkgs.coreutils}/bin/chown -R dms-greeter:dms-greeter /var/lib/dms-greeter
    '';

    # fprintd (enabled on this host) makes NixOS inject `auth sufficient
    # pam_fprintd.so` ahead of pam_unix into /etc/pam.d/greetd. greetd runs that
    # stack for the DankGreeter, whose greetd-protocol auth doesn't drive the
    # interactive fingerprint prompt, so a correct password is rejected. DMS
    # handles fingerprint via its own fprintd path, not this PAM service, so
    # force the greeter (and the DMS lock screen, which falls back to
    # /etc/pam.d/login on NixOS) to a clean password-only pam_unix stack.
    # The nixpkgs DMS greeter module also creates /etc/pam.d/dms-greeter, which
    # gets the same `auth sufficient pam_fprintd.so` ahead of pam_unix — the same
    # setup that previously made the greeter reject correct passwords — so force
    # it to password-only as well.
    security.pam.services = {
      greetd.fprintAuth = false;
      dms-greeter.fprintAuth = false;
      dankshell.fprintAuth = false;
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

    # DMS reads the battery via the UPower DBus daemon (Quickshell.Services.UPower).
    # The nixpkgs DMS module does not enable this, so enable it here or the bar
    # shows no battery.
    services.upower.enable = true;

    # KDE Connect: opens TCP/UDP 1714-1764 for phone pairing. Consumed by the
    # DankKDEConnect ("Phone Connect") DMS plugin, which drives kdeconnectd
    # over D-Bus.
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

        # Declarative / read-only (store symlinks, same as the old DMS home
        # module): GUI edits won't persist. Re-snapshot settings with
        # `cp -L ~/.config/DankMaterialShell/settings.json linux/dms/settings.json`
        # after intentional GUI tuning, then rebuild.
        xdg.stateFile."DankMaterialShell/session.json".source =
          jsonFormat.generate "session.json" dmsSession;

        xdg.configFile = {
          "DankMaterialShell/settings.json".source = jsonFormat.generate "settings.json" (
            lib.importJSON ./dms/settings.json
          );
          "DankMaterialShell/plugin_settings.json".source =
            jsonFormat.generate "plugin_settings.json" dmsPluginSettings;
          # settings.json's customThemeFile. This used to be a GUI-installed
          # registry theme living only in the persisted dir, and it vanished
          # when the shell upgraded to 2.0, so install it declaratively.
          "DankMaterialShell/themes/catppuccin/theme.json".source =
            "${src.registry}/themes/catppuccin/theme.json";

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
      # gnome-keyring stores the encrypted login keyring here; without persistence
      # it'd be recreated empty every boot, discarding saved credentials.
      ".local/share/keyrings"
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
