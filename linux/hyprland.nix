{
  config,
  lib,
  pkgs,
  dmsFlake,
  unstablePkgs,
  ...
}:
let
  cfg = config.agindin.hyprland;
  inherit (lib) mkIf mkEnableOption;

  # Two DMS plugins we install live in monorepos; fetch each repo once and
  # point the individual plugin `src`s at the relevant subdirectory.
  avengeDmsPlugins = pkgs.fetchFromGitHub {
    owner = "AvengeMedia";
    repo = "dms-plugins";
    rev = "f4583449f12920e0a2f16808b00a860c27f0173d";
    hash = "sha256-QkQPqP7Wmo5DLRyKNSY5NuOau4LSaSfz3DYdHDLxluA=";
  };
  nderscoreDmsPlugins = pkgs.fetchFromGitHub {
    owner = "nderscore";
    repo = "dms-plugins";
    rev = "851e06ca204f17a97414a666728246fd3acad3c6";
    hash = "sha256-7sirKRVHVibRJFco4uqPpC7sfwIIqG7bqvDG6EAJSRw=";
  };
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

      # Runtime dependency of the amdGpuMonitorRevive DMS plugin. (mpv, needed
      # by the ambientSound plugin, is already installed via common/mpv.nix.)
      amdgpu_top

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
    # The DMS *NixOS* module would enable this, but we use the home module, so
    # enable it here or the bar shows no battery.
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

          # Third-party DMS plugins. Each attr name MUST equal the plugin's
          # manifest `id` (from its plugin.json): the module installs the source
          # to ~/.config/DankMaterialShell/plugins/<name> AND keys the generated
          # plugin_settings.json by <name>, and DMS matches enabled-state by
          # manifest id — a mismatch installs the plugin but never enables it.
          # Bar-widget plugins also need a layout entry in dms/settings.json
          # (barConfigs); launcher plugins are reached by their trigger string.
          managePluginSettings = true;
          plugins = {
            # Launchers (spotlight triggers): ":e" emoji, "=" calc, "nix" pkgs.
            emojiLauncher.src = pkgs.fetchFromGitHub {
              owner = "devnullvoid";
              repo = "dms-emoji-launcher";
              rev = "8ff394e3ddfcb2fd755ed2e7b4c6f01f3e26e596";
              hash = "sha256-fmIddCvACwO8wbAtLBMtDnEXXQJjb7+o2s4jW3f8VIU=";
            };
            calculator.src = pkgs.fetchFromGitHub {
              owner = "rochacbruno";
              repo = "DankCalculator";
              rev = "1db5865419a40a33171a475855a59e0b8bf7187f";
              hash = "sha256-j8C62+sevr6b+akzVSAqUVysIhb6Vbr8jnWcTXeOtE8=";
            };
            nixPackageRunner.src = pkgs.fetchFromGitHub {
              owner = "iahccc";
              repo = "NixPackageRunner";
              rev = "829ad93c15b7c0ec82a6d7483728029037442601";
              hash = "sha256-ur+1oN+QmTu7p5ZMpL3rCd4JGYbkerko4twa+tH6uvg=";
            };

            # Bar widgets (placed in dms/settings.json barConfigs).
            amdGpuMonitorRevive.src = pkgs.fetchFromGitHub {
              owner = "JDKamalakar";
              repo = "DMS-AMD_GPU_Monitor_Revive";
              rev = "d99d4f0673635a7e71bc457fbbd3319f84c18b52";
              hash = "sha256-/NceDiewqhi55w8psJvOhEhscME/s4bxqykcobCdgtI=";
            };
            ambientSound.src = pkgs.fetchFromGitHub {
              owner = "hthienloc";
              repo = "dms-ambient-sound";
              rev = "d1db2c49ec410a601f2611d805cbfb97aaa7c0cb";
              hash = "sha256-PwmKzTVgEsL8NYuaPXav3gMZtQzSiEdyp1LvuEQX8AU=";
            };
            hyprlandSubmapIndicator.src = "${nderscoreDmsPlugins}/HyprlandSubmapIndicator";
            dankKDEConnect.src = "${avengeDmsPlugins}/DankKDEConnect";
            dankPomodoroTimer.src = "${avengeDmsPlugins}/DankPomodoroTimer";
          };

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
        };

        # DMS bug: gamma control (night mode) is only applied to outputs that
        # exist when the shell starts, so a hotplugged monitor never gets night
        # mode. Until that's fixed upstream, watch Hyprland's event socket and
        # restart DMS whenever a monitor is connected.
        systemd.user.services.dms-monitor-restart = {
          Unit = {
            Description = "Restart DMS when a monitor is connected";
            After = [ "graphical-session.target" ];
            PartOf = [ "graphical-session.target" ];
          };
          Service = {
            ExecStart = lib.getExe (
              pkgs.writeShellApplication {
                name = "dms-monitor-restart";
                runtimeInputs = [ pkgs.socat ];
                text = ''
                  socket="$XDG_RUNTIME_DIR/hypr/$HYPRLAND_INSTANCE_SIGNATURE/.socket2"

                  # The socket can appear slightly after graphical-session.target.
                  for _ in $(seq 1 50); do
                    [[ -S $socket ]] && break
                    sleep 0.2
                  done
                  [[ -S $socket ]]

                  socat -u "UNIX-CONNECT:$socket" - | while IFS= read -r line; do
                    case $line in
                    "monitoradded>>"*)
                      # Let the output settle, then drain the pipe so a burst of
                      # events (e.g. a dock with several displays) coalesces
                      # into a single restart.
                      sleep 2
                      while IFS= read -r -t 0.1 line; do :; done
                      systemctl --user try-restart dms.service
                      ;;
                    esac
                  done
                '';
              }
            );
            # socat exits when Hyprland goes away; always come back up so a
            # compositor restart doesn't leave us dead.
            Restart = "always";
            RestartSec = 2;
          };
          Install.WantedBy = [ "graphical-session.target" ];
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
