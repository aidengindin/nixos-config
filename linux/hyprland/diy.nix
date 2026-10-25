# The DIY desktop around Hyprland: waybar, rofi, swaync, swayosd, hyprlock,
# hypridle, hyprpaper, hyprsunset and a handful of rofi/waybar scripts.
# Everything comes from stable nixpkgs and Home Manager modules; nothing here
# needs a flake input.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.agindin.hyprland;
  inherit (lib) mkIf getExe;

  hmCfg = config.home-manager.users.agindin;
  rofi = hmCfg.programs.rofi.finalPackage;
  hyprctl = "${config.programs.hyprland.package}/bin/hyprctl";
  loginctl = "${pkgs.systemd}/bin/loginctl";
  onAC = "${pkgs.systemd}/bin/systemd-ac-power";
  swayosd = "${pkgs.swayosd}/bin/swayosd-client";
  swaync = "${pkgs.swaynotificationcenter}/bin/swaync-client";

  # The sounds the Dux ambientSound plugin shipped (MIT), pinned to the same
  # commit as that plugin's flake input. A fixed-output fetch, not an input.
  ambientSounds = pkgs.fetchFromGitHub {
    owner = "hthienloc";
    repo = "dms-ambient-sound";
    rev = "83fae75429af7e5eaf9d34b832dd6d2c6f569769";
    hash = "sha256-HenuQh/OHTCzPN5Hlr0atxdLTWn24rxF7KaKOfFbhQg=";
  };

  # Top-level attribute names of the system's nixpkgs, for nix-run's list.
  # Only names are read, so this doesn't evaluate any package.
  nixpkgsNames = pkgs.writeText "nixpkgs-attr-names" (lib.concatLines (builtins.attrNames pkgs));

  # Each script is shellchecked at build time and runs with set -euo pipefail.
  # runtimeInputs are prepended to the session PATH, so kitty/uwsm resolve
  # from the user's environment.
  script =
    name: runtimeInputs: preamble:
    pkgs.writeShellApplication {
      inherit name runtimeInputs;
      text = preamble + builtins.readFile ./scripts/${name}.sh;
    };

  scripts = with pkgs; {
    wifi = script "wifi-menu" [
      networkmanager
      rofi
      libnotify
      wl-clipboard
      gawk
    ] "";
    bluetooth = script "bluetooth-menu" [
      bluez
      rofi
      libnotify
      gawk
      gnused
      gnugrep
    ] "";
    audio = script "audio-menu" [
      pipewire
      wireplumber
      jq
      rofi
      libnotify
    ] "";
    keepAwake = script "keep-awake" [
      systemd
      libnotify
      procps
    ] "";
    power = script "power-menu" [
      rofi
      systemd
    ] "";
    clipboard = script "clipboard-menu" [
      cliphist
      rofi
      wl-clipboard
      libnotify
    ] "";
    pomodoro = script "pomodoro" [
      libnotify
      procps
    ] "";
    gpu = script "gpu-status" [ gawk ] "";
    sysmon = script "sysmon" [
      procps
      gawk
      jq
    ] "";
    brightness = script "brightness" [
      ddcutil
      swayosd
      config.programs.hyprland.package
      jq
      gawk
      util-linux # flock
      procps
      libnotify
    ] "";
    ambient = script "ambient-menu" [
      mpv
      socat
      systemd
      findutils
      rofi
      procps
    ] "sounds_dir=${ambientSounds}/sounds\n";
    nixRun = script "nix-run" [
      config.nix.package
      rofi
      libnotify
    ] "package_list=${nixpkgsNames}\n";
  };

  # Powerline separators between bar segments (Nerd Font glyphs):  ends
  # a segment on its right,  starts one on its left.
  arrow = glyph: {
    format = glyph;
    tooltip = false;
  };

  bar = {
    layer = "top";
    position = "top";
    spacing = 0;

    modules-left = [
      "hyprland/workspaces"
      "custom/arrow-left-end"
      "hyprland/submap"
      "hyprland/window"
    ];
    modules-center = [
      "custom/arrow-clock-start"
      "clock"
      "custom/arrow-clock-end"
    ];
    modules-right = [
      "mpris"
      "privacy"
      "custom/pomodoro"
      "custom/ambient"
      "custom/arrow-stats-start"
      "custom/weather"
      "custom/cpu"
      "custom/memory"
      "temperature"
      "custom/gpu"
      "custom/arrow-stats-end"
      "custom/arrow-controls-start"
      "hyprland/language"
      "network"
      "bluetooth"
      "wireplumber"
      "custom/ddc"
      "backlight"
      "battery"
      "custom/arrow-controls-end"
      "custom/keep-awake"
      "tray"
      "custom/notifications"
      "custom/power"
    ];

    "custom/arrow-left-end" = arrow "";
    "custom/arrow-clock-start" = arrow "";
    "custom/arrow-clock-end" = arrow "";
    "custom/arrow-stats-start" = arrow "";
    "custom/arrow-stats-end" = arrow "";
    "custom/arrow-controls-start" = arrow "";
    "custom/arrow-controls-end" = arrow "";

    "hyprland/workspaces" = {
      sort-by = "id";
      format = "{id}";
      on-scroll-up = "${hyprctl} dispatch workspace e+1";
      on-scroll-down = "${hyprctl} dispatch workspace e-1";
    };
    "hyprland/submap" = {
      format = "󰌌 {}";
      tooltip = false;
    };
    "hyprland/window" = {
      format = "{}";
      max-length = 60;
      separate-outputs = true;
    };

    clock = {
      interval = 5;
      format = "{:%a %d %b  %H:%M}";
      tooltip-format = "<tt>{calendar}</tt>";
      calendar = {
        mode = "month";
        weeks-pos = "left";
        format = {
          today = "<span color='#cba6f7'><b>{}</b></span>";
          weeks = "<span color='#6c7086'>{}</span>";
        };
      };
      on-click = "${swaync} -t -sw";
    };

    mpris = {
      format = "{player_icon} {title}";
      format-paused = "{status_icon} {title}";
      player-icons.default = "󰐊";
      status-icons.paused = "󰏤";
      max-length = 40;
      ignored-players = [ "firefox" ];
    };
    privacy = {
      icon-size = 14;
      modules = [
        { type = "screenshare"; }
        { type = "audio-in"; }
      ];
    };

    "custom/pomodoro" = {
      exec = "${getExe scripts.pomodoro} status";
      return-type = "json";
      interval = 1;
      signal = 8;
      on-click = "${getExe scripts.pomodoro} toggle";
      on-click-right = "${getExe scripts.pomodoro} reset";
      on-click-middle = "${getExe scripts.pomodoro} skip";
    };
    "custom/ambient" = {
      exec = "${getExe scripts.ambient} status";
      return-type = "json";
      interval = 30;
      signal = 10;
      on-click = getExe scripts.ambient;
    };
    "custom/gpu" = {
      exec = getExe scripts.gpu;
      return-type = "json";
      interval = 5;
    };
    # Custom rather than built-in cpu/memory so the tooltips can list the
    # heaviest programs.
    "custom/cpu" = {
      exec = "${getExe scripts.sysmon} cpu";
      return-type = "json";
      interval = 5;
    };
    "custom/memory" = {
      exec = "${getExe scripts.sysmon} memory";
      return-type = "json";
      interval = 10;
    };
    # k10temp's Tctl; hwmonN numbering isn't stable across boots.
    temperature = {
      hwmon-path-abs = "/sys/devices/pci0000:00/0000:00:18.3/hwmon";
      input-filename = "temp1_input";
      critical-threshold = 90;
      format = "󰔏 {temperatureC}°";
    };
    "custom/weather" = {
      exec = "${getExe pkgs.wttrbar} --nerd --fahrenheit --mph";
      return-type = "json";
      interval = 1800;
      format = "{}°";
    };
    "hyprland/language" = {
      format = "{}";
      format-en = "US";
      format-he = "HE";
    };

    network = {
      format-wifi = "{icon}";
      format-icons = [
        "󰤯"
        "󰤟"
        "󰤢"
        "󰤥"
        "󰤨"
      ];
      format-ethernet = "󰈀";
      format-linked = "󰈀";
      format-disconnected = "󰤮";
      tooltip-format-wifi = "{essid} ({signalStrength}%)\n{ipaddr} via {ifname}";
      tooltip-format-ethernet = "{ipaddr} via {ifname}";
      tooltip-format-disconnected = "Disconnected";
      on-click = getExe scripts.wifi;
    };
    bluetooth = {
      format = "󰂯";
      format-off = "󰂲";
      format-disabled = "󰂲";
      format-connected = "󰂱 {num_connections}";
      tooltip-format-connected = "{device_enumerate}";
      tooltip-format-enumerate-connected = "{device_alias}";
      tooltip-format-enumerate-connected-battery = "{device_alias}  {device_battery_percentage}%";
      on-click = getExe scripts.bluetooth;
    };
    wireplumber = {
      format = "{icon} {volume}%";
      format-muted = "󰝟";
      format-icons = [
        "󰕿"
        "󰖀"
        "󰕾"
      ];
      max-volume = 100;
      on-click = getExe scripts.audio;
      on-click-middle = "${swayosd} --output-volume mute-toggle";
      on-click-right = getExe pkgs.pwvucontrol;
      on-scroll-up = "${swayosd} --output-volume raise --max-volume 100";
      on-scroll-down = "${swayosd} --output-volume lower";
    };
    # External monitor brightness over DDC/CI; hidden when none answers.
    "custom/ddc" = {
      exec = "${getExe scripts.brightness} status";
      return-type = "json";
      interval = 60;
      signal = 11;
      on-scroll-up = "${getExe scripts.brightness} up external";
      on-scroll-down = "${getExe scripts.brightness} down external";
    };
    backlight = {
      format = "{icon}";
      format-icons = [
        "󰃞"
        "󰃟"
        "󰃠"
      ];
      tooltip-format = "Brightness {percent}%";
      on-scroll-up = "${swayosd} --brightness raise";
      on-scroll-down = "${swayosd} --brightness lower";
    };
    battery = {
      interval = 60;
      states = {
        warning = 30;
        critical = 15;
      };
      format = "{icon} {capacity}%";
      format-charging = "󰂄 {capacity}%";
      format-plugged = "󰚥 {capacity}%";
      format-icons = [
        "󰂎"
        "󰁺"
        "󰁻"
        "󰁼"
        "󰁽"
        "󰁾"
        "󰁿"
        "󰂀"
        "󰂁"
        "󰂂"
        "󰁹"
      ];
      tooltip-format = "{timeTo}\n{power:0.1f} W · health {health}%";
    };
    "custom/keep-awake" = {
      exec = "${getExe scripts.keepAwake} status";
      return-type = "json";
      interval = 60;
      signal = 9;
      on-click = getExe scripts.keepAwake;
    };
    tray = {
      icon-size = 16;
      spacing = 8;
    };
    "custom/notifications" = {
      exec = "${swaync} -swb";
      return-type = "json";
      format = "{icon}";
      format-icons = {
        notification = "󰂚";
        none = "󰂜";
        dnd-notification = "󰂛";
        dnd-none = "󰂛";
        inhibited-notification = "󰂚";
        inhibited-none = "󰂜";
        dnd-inhibited-notification = "󰂛";
        dnd-inhibited-none = "󰂛";
      };
      tooltip = false;
      escape = true;
      on-click = "${swaync} -t -sw";
      on-click-right = "${swaync} -d -sw";
    };
    "custom/power" = {
      format = "󰐥";
      tooltip = false;
      on-click = getExe scripts.power;
    };
  };

  wallpapers = "/home/agindin/Pictures/wallpapers";
in
{
  config = mkIf (cfg.enable && cfg.shell == "diy") {
    # Shell binds appended to hyprland.lua (mainMod is a local defined there).
    agindin.hyprland.shellLua = ''
      -- DIY shell binds (agindin.hyprland.shell = "diy"), from linux/hyprland/diy.nix.

      -- Volume, with an on-screen display. Brightness keys act on the focused
      -- monitor: the laptop backlight, or an external monitor over DDC/CI.
      hl.bind("XF86AudioRaiseVolume", hl.dsp.exec_cmd("${swayosd} --output-volume raise --max-volume 100"), { locked = true, repeating = true })
      hl.bind("XF86AudioLowerVolume", hl.dsp.exec_cmd("${swayosd} --output-volume lower"), { locked = true, repeating = true })
      hl.bind("XF86AudioMute",        hl.dsp.exec_cmd("${swayosd} --output-volume mute-toggle"), { locked = true })
      hl.bind("XF86AudioMicMute",     hl.dsp.exec_cmd("${swayosd} --input-volume mute-toggle"), { locked = true })
      hl.bind("XF86MonBrightnessUp",   hl.dsp.exec_cmd("${getExe scripts.brightness} up"), { locked = true, repeating = true })
      hl.bind("XF86MonBrightnessDown", hl.dsp.exec_cmd("${getExe scripts.brightness} down"), { locked = true, repeating = true })

      -- Session
      hl.bind(mainMod .. " + O",         hl.dsp.exec_cmd("${loginctl} lock-session"))
      hl.bind(mainMod .. " + X",         hl.dsp.exec_cmd("${getExe scripts.power}"))
      hl.bind(mainMod .. " + SHIFT + I", hl.dsp.exec_cmd("${getExe scripts.keepAwake}"))

      -- Launchers and menus
      hl.bind(mainMod .. " + space",         hl.dsp.exec_cmd("${getExe rofi} -show drun"))
      hl.bind(mainMod .. " + SHIFT + space", hl.dsp.exec_cmd("${getExe scripts.nixRun}"))
      hl.bind(mainMod .. " + period",        hl.dsp.exec_cmd("${getExe rofi} -show emoji"))
      hl.bind(mainMod .. " + equal",         hl.dsp.exec_cmd("${getExe rofi} -show calc -no-show-match -no-sort"))
      hl.bind(mainMod .. " + V",             hl.dsp.exec_cmd("${getExe scripts.clipboard}"))
      hl.bind(mainMod .. " + W",             hl.dsp.exec_cmd("${getExe scripts.wifi}"))
      hl.bind(mainMod .. " + B",             hl.dsp.exec_cmd("${getExe scripts.bluetooth}"))
      hl.bind(mainMod .. " + P",             hl.dsp.exec_cmd("${getExe scripts.audio}"))
      hl.bind(mainMod .. " + SHIFT + A",     hl.dsp.exec_cmd("${getExe scripts.ambient}"))

      -- Notification centre
      hl.bind(mainMod .. " + A", hl.dsp.exec_cmd("${swaync} -t -sw"))
    '';

    environment.systemPackages = [ pkgs.pwvucontrol ];

    # Login: tuigreet on greetd. It remembers the last user and session in
    # /var/cache/tuigreet (persisted below).
    services.greetd = {
      enable = true;
      settings.default_session = {
        user = "greeter";
        command = lib.concatStringsSep " " [
          (getExe pkgs.tuigreet)
          "--time"
          "--asterisks"
          "--remember"
          "--remember-session"
          "--sessions ${config.services.displayManager.sessionData.desktops}/share/wayland-sessions"
          "--cmd 'uwsm start hyprland-uwsm.desktop'"
        ];
      };
    };

    # Keep boot/kernel messages from scribbling over the greeter.
    systemd.services.greetd.serviceConfig = {
      Type = "idle";
      StandardInput = "tty";
      StandardOutput = "tty";
      StandardError = "journal";
      TTYReset = true;
      TTYVHangup = true;
      TTYVTDisallocate = true;
    };

    # The persisted cache is bind-mounted in before greetd starts; make sure
    # the greeter user owns it whatever state an earlier generation left.
    systemd.services.greetd.preStart = lib.mkAfter ''
      ${pkgs.coreutils}/bin/mkdir -p /var/cache/tuigreet
      ${pkgs.coreutils}/bin/chown -R greeter:greeter /var/cache/tuigreet
    '';

    # hyprlock's PAM service. fprintd would put pam_fprintd ahead of pam_unix
    # here too, blocking password entry until the fingerprint times out;
    # hyprlock drives the reader itself (auth.fingerprint below) instead.
    programs.hyprlock.enable = true;
    security.pam.services.hyprlock.fprintAuth = false;

    home-manager.users.agindin = {
      programs.waybar = {
        enable = true;
        systemd.enable = true;
        style = builtins.readFile ./waybar.css;
        settings.main = bar;
      };

      programs.rofi = {
        enable = true;
        plugins = with pkgs; [
          rofi-calc
          rofi-emoji
        ];
        font = "Hasklug Nerd Font 12";
        terminal = "kitty";
        theme = "catppuccin-default";
        extraConfig = {
          modi = "drun,run,calc,emoji";
          show-icons = true;
          display-drun = "Apps";
          drun-display-format = "{name}";
        };
      };
      # Looked up by name; catppuccin-default.rasi @imports catppuccin-mocha.
      xdg.dataFile = {
        "rofi/themes/catppuccin-default.rasi".source = ./rofi/catppuccin-default.rasi;
        "rofi/themes/catppuccin-mocha.rasi".source = ./rofi/catppuccin-mocha.rasi;
      };

      services.swaync = {
        enable = true;
        style = builtins.readFile ./swaync/style.css;
        settings = {
          positionX = "right";
          positionY = "top";
          control-center-width = 420;
          notification-window-width = 380;
          notification-icon-size = 48;
          notification-body-image-height = 100;
          notification-body-image-width = 200;
          timeout = 5;
          timeout-low = 5;
          timeout-critical = 0;
          keyboard-shortcuts = true;
          image-visibility = "when-available";
          transition-time = 200;
          hide-on-clear = true;
          hide-on-action = true;
          widgets = [
            "title"
            "dnd"
            "mpris"
            "notifications"
          ];
          widget-config = {
            title = {
              text = "Notifications";
              clear-all-button = true;
              button-text = "Clear all";
            };
            dnd.text = "Do not disturb";
            mpris.image-size = 96;
          };
        };
      };

      services.swayosd = {
        enable = true;
        stylePath = ./swayosd.css;
      };
      # Replaces the package's /etc/xdg/swayosd/config.toml, so keep its
      # min_brightness. top_margin: 0 is the top edge, 1 the bottom edge.
      xdg.configFile."swayosd/config.toml".text = ''
        [server]
        top_margin = 0.94
        show_percentage = true
        max_volume = 100
        min_brightness = 5
      '';
      services.cliphist.enable = true;
      services.poweralertd.enable = true;
      services.hyprpolkitagent.enable = true;
      services.kdeconnect = {
        enable = true;
        indicator = true;
      };

      services.hyprpaper = {
        enable = true;
        settings = {
          splash = false;
          wallpaper = [
            {
              monitor = "eDP-1";
              path = "${wallpapers}/nixos.png";
            }
            {
              monitor = "desc:HP Inc. OMEN 34c";
              path = "${wallpapers}/stormlight-ultrawide.png";
            }
            # Any other display.
            {
              monitor = "";
              path = "${wallpapers}/nixos.png";
            }
          ];
        };
      };

      # Night light: 2500K from 19:00 to 05:00 (same schedule Dux used).
      services.hyprsunset = {
        enable = true;
        settings.profile = [
          {
            time = "5:00";
            identity = true;
          }
          {
            time = "19:00";
            temperature = 2500;
          }
        ];
      };

      # Idle: same timeouts Dux used, which differ on battery and AC power.
      # Each step has a battery listener (skipped on AC via systemd-ac-power)
      # and a later unconditional one for AC.
      #             battery   AC
      #   dim        2.5 min  2.5 min
      #   lock       5 min    10 min
      #   screen off 6 min    11 min   (1 min after locking)
      #   suspend    15 min   30 min
      # Keep awake (bar / Super+Shift+I) holds an idle inhibitor, which
      # hypridle respects, so none of these fire while it's on.
      services.hypridle = {
        enable = true;
        settings = {
          general = {
            lock_cmd = "${pkgs.procps}/bin/pidof hyprlock || ${getExe pkgs.hyprlock}";
            before_sleep_cmd = "${loginctl} lock-session";
            after_sleep_cmd = "${hyprctl} dispatch dpms on";
          };
          listener =
            let
              brightnessctl = getExe pkgs.brightnessctl;
              lock = "${loginctl} lock-session";
              screenOff = "${hyprctl} dispatch dpms off";
              screenOn = "${hyprctl} dispatch dpms on";
              suspend = "${pkgs.systemd}/bin/systemctl suspend";
            in
            [
              {
                timeout = 150;
                on-timeout = "${brightnessctl} -s set 10%";
                on-resume = "${brightnessctl} -r";
              }
              {
                timeout = 300;
                on-timeout = "${onAC} || ${lock}";
              }
              {
                timeout = 360;
                on-timeout = "${onAC} || ${screenOff}";
                on-resume = screenOn;
              }
              {
                timeout = 600;
                on-timeout = lock;
              }
              {
                timeout = 660;
                on-timeout = screenOff;
                on-resume = screenOn;
              }
              {
                timeout = 900;
                on-timeout = "${onAC} || ${suspend}";
              }
              {
                timeout = 1800;
                on-timeout = suspend;
              }
            ];
        };
      };

      programs.hyprlock = {
        enable = true;
        settings = {
          general = {
            hide_cursor = true;
            grace = 0;
          };
          auth.fingerprint.enabled = config.services.fprintd.enable;
          background = [
            {
              path = "screenshot";
              blur_passes = 3;
              blur_size = 8;
              brightness = 0.6;
            }
          ];
          label = [
            {
              text = "$TIME";
              font_family = "Hasklug Nerd Font";
              font_size = 96;
              color = "rgb(cdd6f4)";
              position = "0, 160";
              halign = "center";
              valign = "center";
            }
            {
              text = ''cmd[update:60000] date +"%A, %d %B"'';
              font_family = "Hasklug Nerd Font";
              font_size = 20;
              color = "rgb(bac2de)";
              position = "0, 70";
              halign = "center";
              valign = "center";
            }
            {
              text = "$FPRINTPROMPT";
              font_family = "Hasklug Nerd Font";
              font_size = 14;
              color = "rgb(a6adc8)";
              position = "0, -110";
              halign = "center";
              valign = "center";
            }
          ];
          input-field = [
            {
              size = "300, 48";
              position = "0, -40";
              halign = "center";
              valign = "center";
              outline_thickness = 2;
              rounding = 8;
              outer_color = "rgb(45475a)";
              inner_color = "rgb(1e1e2e)";
              font_color = "rgb(cdd6f4)";
              check_color = "rgb(f9e2af)";
              fail_color = "rgb(f38ba8)";
              capslock_color = "rgb(fab387)";
              dots_size = 0.25;
              dots_spacing = 0.3;
              fade_on_empty = false;
              placeholder_text = "<span foreground=\"##6c7086\">Password</span>";
              fail_text = "$FAIL ($ATTEMPTS)";
            }
          ];
        };
      };
    };

    agindin.impermanence.systemDirectories = mkIf config.agindin.impermanence.enable [
      "/var/cache/tuigreet"
    ];
  };
}
