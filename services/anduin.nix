{
  config,
  lib,
  pkgs,
  customPkgs,
  ...
}:
let
  cfg = config.agindin.services.anduin;
  inherit (lib)
    mkIf
    mkEnableOption
    mkOption
    types
    ;

  # Mirrors anduin's config.py FileConfig; secrets come from the EnvironmentFile.
  configJson = pkgs.writeText "anduin-config.json" (
    builtins.toJSON {
      state_dir = "/var/lib/anduin/state";
      google_health = {
        enabled = cfg.google-health.enable;
        backfill_window_days = cfg.google-health.backfillWindowDays;
      };
      withings = {
        enabled = cfg.withings.enable;
        window_days = cfg.withings.windowDays;
      };
      intervals = {
        enabled = cfg.intervals.enable;
        window_days = cfg.intervals.windowDays;
        pull_streams = cfg.intervals.pullStreams;
      };
      liftosaur = {
        enabled = cfg.liftosaur.enable;
        window_days = cfg.liftosaur.windowDays;
      };
      headache = {
        enabled = cfg.headache.enable;
        app_url = cfg.headache.appUrl;
        ntfy_url = cfg.headache.ntfyUrl;
        remind_skip_within_minutes = cfg.headache.skipWithinMinutes;
      };
    }
  );

  # Copied from services/headache-sync.nix; extractors reach the network + a
  # local-forwarded TCP socket, and refresh OAuth tokens under STATE_DIRECTORY.
  hardening = {
    NoNewPrivileges = true;
    PrivateTmp = true;
    PrivateDevices = true;
    ProtectClock = true;
    ProtectSystem = "strict";
    ProtectHome = true;
    ProtectKernelTunables = true;
    ProtectKernelModules = true;
    ProtectKernelLogs = true;
    ProtectControlGroups = true;
    ProtectHostname = true;
    LockPersonality = true;
    MemoryDenyWriteExecute = true;
    RestrictRealtime = true;
    RestrictSUIDSGID = true;
    RestrictNamespaces = true;
    RestrictAddressFamilies = [
      "AF_INET"
      "AF_INET6"
      "AF_UNIX"
    ];
    CapabilityBoundingSet = "";
    SystemCallFilter = [
      "@system-service"
      "~@resources"
      "~@privileged"
    ];
    SystemCallArchitectures = "native";
  };

  # One oneshot per source. All share StateDirectory=anduin/state so tokens land
  # at /var/lib/anduin/state/<source>/token.json — the same path `anduin auth`
  # writes to (config.py lets systemd's STATE_DIRECTORY override state_dir).
  mkExtractor = name: {
    description = "anduin ${name} extractor";
    after = [
      "network-online.target"
      "anduin-db-migrate.service"
    ];
    wants = [ "network-online.target" ];
    requires = [ "anduin-db-migrate.service" ];
    serviceConfig = hardening // {
      Type = "oneshot";
      User = cfg.user;
      Group = cfg.group;
      EnvironmentFile = cfg.environmentFile;
      Environment = [ "ANDUIN_CONFIG=${configJson}" ];
      StateDirectory = "anduin/state";
      StateDirectoryMode = "0700";
      ExecStart = "${cfg.package}/bin/anduin extract ${name}";
    };
  };

  # `container@anduin-postgres.service` going active only means the container
  # booted — postgres inside may still be running first-boot initdb + ensure*.
  # Block until it actually accepts connections. Reads host/port from
  # DATABASE_URL (loaded from the EnvironmentFile), so nothing is hardcoded.
  waitForDb = pkgs.writeShellScript "anduin-wait-db" ''
    for _ in $(seq 1 60); do
      ${pkgs.postgresql_16}/bin/pg_isready -q -d "$DATABASE_URL" && exit 0
      sleep 2
    done
    echo "anduin: database not ready after 120s" >&2
    exit 1
  '';

  mkTimer = name: schedule: {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = schedule;
      Persistent = true;
      RandomizedDelaySec = "5m";
      Unit = "anduin-${name}.service";
    };
  };
in
{
  options.agindin.services.anduin = {
    enable = mkEnableOption "anduin health data pipeline";

    package = mkOption {
      type = types.package;
      default = customPkgs.anduin;
      description = "anduin derivation. Defaults to the anduin flake input via customPkgs.";
    };

    user = mkOption {
      type = types.str;
      default = "anduin";
    };
    group = mkOption {
      type = types.str;
      default = "anduin";
    };

    environmentFile = mkOption {
      type = types.path;
      description = ''
        Agenix-decrypted env file. Must define DATABASE_URL and the secrets for
        each enabled source (GOOGLE_HEALTH_CLIENT_ID/SECRET, WITHINGS_CLIENT_ID/
        SECRET, INTERVALS_API_KEY, INTERVALS_ATHLETE_ID, LIFTOSAUR_API_KEY, plus
        NTFY_TOPIC when headache reminders are enabled).
      '';
    };

    google-health = {
      enable = mkEnableOption "Google Health extractor";
      schedule = mkOption {
        type = types.listOf types.str;
        default = [
          "*-*-* *:17:00" # hourly today-window pull
          "*-*-* 02:30:00" # nightly backfill
        ];
      };
      backfillWindowDays = mkOption {
        type = types.ints.positive;
        default = 7;
      };
    };
    withings = {
      enable = mkEnableOption "Withings (body weight) extractor";
      schedule = mkOption {
        type = types.listOf types.str;
        default = [ "*-*-* 03,09,15,21:00:00" ]; # every 6h
      };
      windowDays = mkOption {
        type = types.ints.positive;
        default = 14;
      };
    };
    intervals = {
      enable = mkEnableOption "intervals.icu extractor";
      schedule = mkOption {
        type = types.listOf types.str;
        default = [ "*-*-* *:23:00" ]; # hourly
      };
      windowDays = mkOption {
        type = types.ints.positive;
        default = 3;
      };
      pullStreams = mkOption {
        type = types.bool;
        default = true;
      };
    };
    liftosaur = {
      enable = mkEnableOption "Liftosaur extractor";
      schedule = mkOption {
        type = types.listOf types.str;
        default = [ "*-*-* *:43:00" ]; # hourly
      };
      windowDays = mkOption {
        type = types.ints.positive;
        default = 7;
      };
    };

    headache = {
      enable = mkEnableOption "headache check-in reminders over ntfy";
      # Local wall-clock times. The timer runs in the host's time.timeZone
      # (America/New_York, see linux/locale.nix), which is also the civil date
      # an ntfy-sourced check-in is filed under.
      schedule = mkOption {
        type = types.listOf types.str;
        default = [ "*-*-* 08,12,16,20:00:00" ];
      };
      appUrl = mkOption {
        type = types.str;
        default = "https://${cfg.web.domain}";
        description = ''
          URL the *phone* reaches anduin on. Both ntfy action buttons point
          here, so it must be routable from the ntfy client — the Caddy vhost,
          not the loopback address `anduin serve` binds.
        '';
      };
      ntfyUrl = mkOption {
        type = types.str;
        default = "https://ntfy.sh";
      };
      skipWithinMinutes = mkOption {
        type = types.ints.positive;
        default = 120;
        description = "Suppress a reminder this many minutes after a check-in.";
      };
    };

    web = {
      enable = mkEnableOption "read-only web UI (anduin serve)";
      domain = mkOption {
        type = types.str;
        default = "anduin.gindin.xyz";
        description = "Public hostname Caddy terminates TLS for and proxies to the UI.";
      };
      port = mkOption {
        type = types.port;
        default = 8080;
        description = ''
          Loopback port `anduin serve` binds. Caddy proxies the public host to it
          and Prometheus scrapes its `/-/metrics` on the same port. Prefer
          `globalVars.ports.anduinWeb` over the default.
        '';
      };
    };
  };

  config = mkIf cfg.enable {
    users.users.${cfg.user} = {
      isSystemUser = true;
      group = cfg.group;
      description = "anduin service user";
    };
    users.groups.${cfg.group} = { };

    # Persist OAuth tokens (under /var/lib/anduin/state) through impermanence.
    agindin.impermanence.systemDirectories = mkIf config.agindin.impermanence.enable [
      "/var/lib/anduin"
    ];

    # Own the state tree explicitly. Under impermanence /var/lib/anduin is a
    # root-owned bind mount, and systemd's StateDirectory= only materializes
    # when a unit runs (and won't re-own that mountpoint) — so the interactive
    # `anduin-auth` seeder, run before any timer fires, couldn't create the
    # token subdir. tmpfiles runs at boot and (re)chowns to the service user.
    systemd.tmpfiles.rules = [
      "d /var/lib/anduin 0750 ${cfg.user} ${cfg.group} -"
      "d /var/lib/anduin/state 0700 ${cfg.user} ${cfg.group} -"
    ];

    systemd.services.anduin-db-migrate = {
      description = "anduin DB migrations (idempotent)";
      after = [ "container@anduin-postgres.service" ];
      requires = [ "container@anduin-postgres.service" ];
      wantedBy = [ "multi-user.target" ];
      serviceConfig = hardening // {
        Type = "oneshot";
        User = cfg.user;
        Group = cfg.group;
        EnvironmentFile = cfg.environmentFile;
        Environment = [ "ANDUIN_CONFIG=${configJson}" ];
        ExecStartPre = waitForDb;
        ExecStart = "${cfg.package}/bin/anduin db migrate";
      };
    };

    systemd.services.anduin-google-health = mkIf cfg.google-health.enable (mkExtractor "google-health");
    systemd.services.anduin-withings = mkIf cfg.withings.enable (mkExtractor "withings");
    systemd.services.anduin-intervals = mkIf cfg.intervals.enable (mkExtractor "intervals");
    systemd.services.anduin-liftosaur = mkIf cfg.liftosaur.enable (mkExtractor "liftosaur");

    systemd.timers.anduin-google-health = mkIf cfg.google-health.enable (
      mkTimer "google-health" cfg.google-health.schedule
    );
    systemd.timers.anduin-withings = mkIf cfg.withings.enable (
      mkTimer "withings" cfg.withings.schedule
    );
    systemd.timers.anduin-intervals = mkIf cfg.intervals.enable (
      mkTimer "intervals" cfg.intervals.schedule
    );
    systemd.timers.anduin-liftosaur = mkIf cfg.liftosaur.enable (
      mkTimer "liftosaur" cfg.liftosaur.schedule
    );

    # Check-in prompt over ntfy. Same env file and config as the extractors,
    # but no StateDirectory — there is no OAuth token; it reads the last
    # check-in from the DB and publishes one notification.
    systemd.services.anduin-remind-headache = mkIf cfg.headache.enable {
      description = "anduin headache check-in reminder (ntfy)";
      after = [
        "network-online.target"
        "anduin-db-migrate.service"
      ];
      wants = [ "network-online.target" ];
      requires = [ "anduin-db-migrate.service" ];
      serviceConfig = hardening // {
        Type = "oneshot";
        User = cfg.user;
        Group = cfg.group;
        EnvironmentFile = cfg.environmentFile;
        Environment = [ "ANDUIN_CONFIG=${configJson}" ];
        ExecStartPre = waitForDb;
        ExecStart = "${cfg.package}/bin/anduin remind headache";
      };
    };

    # Deliberately not mkTimer: a prompt should land at the time chosen (no
    # RandomizedDelaySec), and a missed 9am prompt must not fire at 3pm
    # (Persistent = false).
    systemd.timers.anduin-remind-headache = mkIf cfg.headache.enable {
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = cfg.headache.schedule;
        Persistent = false;
        Unit = "anduin-remind-headache.service";
      };
    };

    # Long-running read-only web UI. Binds loopback only; Caddy terminates TLS
    # and reverse-proxies the public host to it (same pattern as grafana), and
    # Prometheus scrapes its /-/metrics on that same loopback port. Reuses the
    # extractor hardening block; `serve` only needs outbound DB + inbound TCP,
    # both already permitted by RestrictAddressFamilies.
    systemd.services.anduin-web = mkIf cfg.web.enable {
      description = "anduin read-only web UI";
      after = [
        "network-online.target"
        "anduin-db-migrate.service"
        "container@anduin-postgres.service"
      ];
      wants = [ "network-online.target" ];
      requires = [ "anduin-db-migrate.service" ];
      wantedBy = [ "multi-user.target" ];
      serviceConfig = hardening // {
        Type = "simple";
        User = cfg.user;
        Group = cfg.group;
        EnvironmentFile = cfg.environmentFile; # needs DATABASE_URL
        Environment = [ "ANDUIN_CONFIG=${configJson}" ];
        ExecStart = "${cfg.package}/bin/anduin serve --host 127.0.0.1 --port ${toString cfg.web.port}";
        Restart = "on-failure";
      };
    };

    # Public route via the shared Caddy module (host defaults to 127.0.0.1).
    agindin.services.caddy.proxyHosts = mkIf cfg.web.enable [
      {
        domain = cfg.web.domain;
        port = cfg.web.port;
      }
    ];

    # One-time interactive OAuth seeding for google-health / withings. Runs the
    # CLI as the anduin user with the same config + env the timers use, so the
    # token lands at the path the extractors read. Forward the redirect port
    # (default 8765) back to your laptop over SSH, then follow the printed URL.
    environment.systemPackages = [
      (pkgs.writeShellScriptBin "anduin-auth" ''
        if [ -z "$1" ]; then
          echo "usage: anduin-auth <google-health|withings>" >&2
          exit 2
        fi
        # pydantic-settings opens ./.env relative to CWD; sudo keeps the caller's
        # CWD (e.g. /home/agindin), which the anduin system user can't read (that
        # is a fatal EACCES, unlike a plain missing .env). Run from a readable dir.
        exec sudo -u ${cfg.user} \
          env -C / $(cat ${cfg.environmentFile} | xargs) \
          STATE_DIRECTORY=/var/lib/anduin/state \
          ANDUIN_CONFIG=${configJson} \
          ${cfg.package}/bin/anduin auth "$1"
      '')
    ];
  };
}
