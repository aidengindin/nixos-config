{
  config,
  lib,
  pkgs,
  customPkgs,
  ...
}:
let
  cfg = config.agindin.services.headache-sync;
  inherit (lib)
    mkIf
    mkEnableOption
    mkOption
    types
    literalExpression
    ;

  configJson = pkgs.writeText "headache-sync-config.json" (
    builtins.toJSON {
      airtable = {
        base_id = cfg.airtable.baseId;
        table_id = cfg.airtable.tableId;
        date_field = cfg.airtable.dateField;
        location_field = cfg.airtable.locationField;
        field_map = cfg.airtable.fieldMap;
      };
      intervals = {
        athlete_id = cfg.intervals.athleteId;
      };
      location = {
        default = cfg.location.default;
        cache_path = cfg.location.cachePath;
      };
      window_days = cfg.windowDays;
    }
  );
in
{
  options.agindin.services.headache-sync = {
    enable = mkEnableOption "headache-sync Airtable populator";

    package = mkOption {
      type = types.package;
      default = customPkgs.headache-sync;
      description = "headache-sync derivation. Defaults to the auto-headache-tracker flake input via customPkgs.";
    };

    user = mkOption {
      type = types.str;
      default = "headache-sync";
    };
    group = mkOption {
      type = types.str;
      default = "headache-sync";
    };

    environmentFile = mkOption {
      type = types.path;
      description = "Path to the age-decrypted env file with AIRTABLE_PAT, INTERVALS_API_KEY, GOOGLE_POLLEN_API_KEY.";
    };

    schedules = mkOption {
      type = types.listOf types.str;
      default = [
        "*-*-* 09:00:00"
        "*-*-* 21:00:00"
      ];
      description = ''
        List of systemd OnCalendar expressions. Each fires the same idempotent job.
        Defaults to twice daily so a late-entered Location on today's row still gets
        a correct Google Pollen capture before midnight.
      '';
    };

    intervals.athleteId = mkOption {
      type = types.str;
      description = "intervals.icu athlete ID, e.g. i12345.";
    };

    airtable = {
      baseId = mkOption {
        type = types.str;
        example = "app6w70TNVJDxqulT";
      };
      tableId = mkOption {
        type = types.str;
        example = "tbl7fY07el677Jm1L";
        description = "Prefer the table ID (tbl…) over its name — stable across renames.";
      };
      dateField = mkOption {
        type = types.str;
        default = "Date";
      };
      locationField = mkOption {
        type = types.str;
        default = "Location";
        description = "Free-text city column read per date to drive weather/AQI/pollen lookup.";
      };
      fieldMap = mkOption {
        type = types.attrsOf types.str;
        description = ''
          Map from internal source-field ID to Airtable column name. Only fields
          present here are written. Missing entries suppress the source field.
        '';
        example = literalExpression ''
          {
            sleep_score = "Sleep score";
            hrv = "HRV";
            resting_hr = "RHR";
            tss = "TSS";
            barometric_pressure = "Barometric pressure (inHg)";
            us_aqi = "AQI";
            pm2_5 = "PM2.5";
            tree_pollen = "Tree pollen (UPI)";
            grass_pollen = "Grass pollen (UPI)";
            weed_pollen = "Weed pollen (UPI)";
          }
        '';
      };
    };

    location = {
      default = mkOption {
        type = types.str;
        example = "Jersey City, NJ";
        description = ''
          Free-text city name used when the Airtable Location cell is blank for a
          date, and to anchor the rolling-window date boundary's timezone.
        '';
      };
      cachePath = mkOption {
        type = types.str;
        default = "/var/lib/headache-sync/geocode-cache.json";
        description = "Persisted geocode cache (Location string → lat/lon/timezone).";
      };
    };

    windowDays = mkOption {
      type = types.ints.positive;
      default = 3;
      description = "Number of trailing days the rolling default window covers.";
    };
  };

  config = mkIf cfg.enable {
    users.users.${cfg.user} = {
      isSystemUser = true;
      group = cfg.group;
      description = "headache-sync service user";
    };
    users.groups.${cfg.group} = { };

    systemd.services.headache-sync = {
      description = "Auto-populate derivable Airtable headache-tracker columns";
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      serviceConfig = {
        Type = "oneshot";
        User = cfg.user;
        Group = cfg.group;
        EnvironmentFile = cfg.environmentFile;
        Environment = [ "HEADACHE_SYNC_CONFIG=${configJson}" ];
        ExecStart = "${cfg.package}/bin/headache-sync";
        StateDirectory = "headache-sync";
        StateDirectoryMode = "0700";
        ReadWritePaths = [ "/var/lib/headache-sync" ];

        # Hardening — mirrors services/withings-sync.nix
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

    systemd.timers.headache-sync = {
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = cfg.schedules;
        Persistent = true;
        RandomizedDelaySec = "5m";
        Unit = "headache-sync.service";
      };
    };
  };
}
