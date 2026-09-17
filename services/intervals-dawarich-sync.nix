{
  config,
  lib,
  customPkgs,
  ...
}:
let
  cfg = config.agindin.services.intervals-dawarich-sync;
  inherit (lib)
    mkIf
    mkEnableOption
    mkOption
    types
    ;

  stateDir = "/var/lib/intervals-dawarich-sync";
in
{
  options.agindin.services.intervals-dawarich-sync = {
    enable = mkEnableOption "intervals.icu -> Dawarich GPX sync";

    package = mkOption {
      type = types.package;
      default = customPkgs.intervals-dawarich-sync;
    };

    user = mkOption {
      type = types.str;
      default = "intervals-dawarich-sync";
    };
    group = mkOption {
      type = types.str;
      default = "intervals-dawarich-sync";
    };

    environmentFile = mkOption {
      type = types.path;
      description = "Age-decrypted env file with INTERVALS_API_KEY and DAWARICH_API_KEY.";
    };

    athleteId = mkOption {
      type = types.str;
      example = "i12345";
      description = "intervals.icu athlete ID.";
    };

    dawarichUrl = mkOption {
      type = types.str;
      default = "https://${config.agindin.services.dawarich.domain}";
      defaultText = "https://\${config.agindin.services.dawarich.domain}";
      description = ''
        Base URL of the Dawarich instance. This has to be the public URL rather
        than 127.0.0.1: Dawarich runs with APPLICATION_PROTOCOL=https, so Rails'
        force_ssl redirects any plain-HTTP request instead of serving it.
      '';
    };

    schedule = mkOption {
      type = types.str;
      default = "hourly";
      description = "systemd OnCalendar expression.";
    };

    lookbackDays = mkOption {
      type = types.ints.positive;
      default = 14;
      description = ''
        How far back each run looks once the initial full-history backfill has
        completed. Wide enough that a few days of downtime still heals itself.
      '';
    };

    uploadDelaySeconds = mkOption {
      type = types.numbers.nonnegative;
      default = 2;
      description = ''
        Pause between uploads. Exists for the first run, which imports the
        entire history: without it Dawarich's Sidekiq queue takes the whole
        backlog at once.
      '';
    };
  };

  config = mkIf cfg.enable {
    users.users.${cfg.user} = {
      isSystemUser = true;
      group = cfg.group;
      description = "intervals.icu -> Dawarich sync service user";
    };
    users.groups.${cfg.group} = { };

    systemd.services.intervals-dawarich-sync = {
      description = "Import GPS-bearing intervals.icu activities into Dawarich";
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      serviceConfig = {
        Type = "oneshot";
        User = cfg.user;
        Group = cfg.group;
        EnvironmentFile = cfg.environmentFile;
        Environment = [
          "INTERVALS_ATHLETE_ID=${cfg.athleteId}"
          "DAWARICH_URL=${cfg.dawarichUrl}"
          "STATE_PATH=${stateDir}/state.json"
          "LOOKBACK_DAYS=${toString cfg.lookbackDays}"
          "UPLOAD_DELAY_SECONDS=${toString cfg.uploadDelaySeconds}"
        ];
        ExecStart = "${cfg.package}/bin/intervals-dawarich-sync";
        StateDirectory = "intervals-dawarich-sync";
        StateDirectoryMode = "0700";
        ReadWritePaths = [ stateDir ];

        # Hardening — mirrors services/headache-sync.nix
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
        ];
        CapabilityBoundingSet = "";
        SystemCallFilter = [
          "@system-service"
          "~@resources"
          "~@privileged"
        ];
        SystemCallArchitectures = "native";
      };
    };

    systemd.timers.intervals-dawarich-sync = {
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = cfg.schedule;
        Persistent = true;
        RandomizedDelaySec = "5m";
      };
    };

    # The state file is what stops a redeploy from re-importing every activity.
    agindin.services.restic.paths = mkIf config.agindin.services.restic.enable [ stateDir ];

    agindin.impermanence.systemDirectories = mkIf config.agindin.impermanence.enable [ stateDir ];
  };
}
