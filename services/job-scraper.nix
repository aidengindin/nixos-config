{
  config,
  lib,
  pkgs,
  customPkgs,
  ...
}:
let
  cfg = config.agindin.services.job-scraper;
  inherit (lib)
    mkIf
    mkEnableOption
    mkOption
    types
    literalExpression
    ;

  configJson = pkgs.writeText "job-scraper-config.json" (
    builtins.toJSON {
      companies_csv = cfg.companiesCsv;
      profile_path = cfg.profilePath;
      state_db = "${cfg.stateDir}/state.db";
      fit_threshold = cfg.fitThreshold;
      concurrency = cfg.concurrency;
      llm = {
        base_url = cfg.llm.baseUrl;
        model = cfg.llm.model;
        max_jd_chars = cfg.llm.maxJdChars;
      };
      sheet = {
        spreadsheet_id = cfg.spreadsheetId;
        sheet_name = cfg.sheetName;
        credentials_file = cfg.googleCredentialsFile;
      };
      ntfy = {
        url = cfg.ntfyUrl;
      };
      filters = cfg.filterOverrides;
    }
  );
in
{
  options.agindin.services.job-scraper = {
    enable = mkEnableOption "job-scraper target-company posting monitor";

    package = mkOption {
      type = types.package;
      default = customPkgs.job-scraper;
      description = "job-scraper derivation. Defaults to the job-scraper flake input via customPkgs.";
    };

    user = mkOption {
      type = types.str;
      default = "job-scraper";
    };
    group = mkOption {
      type = types.str;
      default = "job-scraper";
    };

    stateDir = mkOption {
      type = types.str;
      default = "/var/lib/job-scraper";
      description = ''
        Holds state.db, the record of every posting already reported. Must
        persist across reboots — losing it re-appends every currently-open
        posting on the next run. The module registers it with impermanence
        automatically.
      '';
    };

    environmentFile = mkOption {
      type = types.path;
      description = "Path to the age-decrypted env file with OPENROUTER_API_KEY and NTFY_TOPIC.";
    };

    googleCredentialsFile = mkOption {
      type = types.str;
      description = ''
        Path to the age-decrypted Google service-account JSON key. The sheet must
        be shared with that service account's address as an Editor.
      '';
    };

    spreadsheetId = mkOption {
      type = types.str;
      example = "1BxiMVs0XRA5nFMdKvBdBZjgmUUqptlbs74OgvE2upms";
      description = "The ID from the sheet URL: docs.google.com/spreadsheets/d/<ID>/edit";
    };

    sheetName = mkOption {
      type = types.str;
      default = "Postings";
      description = "Tab name within the spreadsheet. Appended to, never rewritten.";
    };

    companiesCsv = mkOption {
      type = types.str;
      default = "${cfg.package}/share/job-scraper/target-companies.csv";
      defaultText = literalExpression ''"''${cfg.package}/share/job-scraper/target-companies.csv"'';
      description = ''
        The watch list. Only rows with status=automated are scraped. Ships with
        the package, so adding a company means editing the CSV in the
        job-scraper repo and bumping the flake input — `discover-boards` is run
        there, not here, since the store path is read-only.
      '';
    };

    profilePath = mkOption {
      type = types.str;
      default = "${cfg.package}/share/job-scraper/target-profile.md";
      defaultText = literalExpression ''"''${cfg.package}/share/job-scraper/target-profile.md"'';
      description = "Target profile the LLM scores each posting against.";
    };

    fitThreshold = mkOption {
      type = types.ints.between 0 10;
      default = 6;
      description = ''
        Minimum fit score to land in the sheet. Postings the model failed to
        score are written regardless, flagged `unscored`.
      '';
    };

    concurrency = mkOption {
      type = types.ints.positive;
      default = 8;
      description = "Number of boards fetched in parallel.";
    };

    llm = {
      baseUrl = mkOption {
        type = types.str;
        default = "https://openrouter.ai/api/v1";
        description = "Any OpenAI-compatible chat-completions endpoint.";
      };
      model = mkOption {
        type = types.str;
        default = "openai/gpt-5.6-luna";
        description = "Model slug as the provider spells it.";
      };
      maxJdChars = mkOption {
        type = types.ints.positive;
        default = 12000;
        description = "Job descriptions are truncated to this length before scoring.";
      };
    };

    ntfyUrl = mkOption {
      type = types.str;
      default = "https://ntfy.sh";
      description = "ntfy server. The topic itself comes from NTFY_TOPIC in the environment file.";
    };

    filterOverrides = mkOption {
      type = types.attrsOf (types.listOf types.str);
      default = { };
      description = ''
        Overrides for the keyword prefilter lists in the app's filters.py —
        `title_include`, `title_exclude`, `nyc`, `remote`, `remote_exclusions`,
        `pipeline_de`. Each key replaces that list wholesale. Lets the rules be
        tuned from here instead of through a package bump.
      '';
      example = literalExpression ''
        {
          title_exclude = [ "\\bfrontend\\b" "\\bfull[- ]?stack\\b" ];
        }
      '';
    };

    schedules = mkOption {
      type = types.listOf types.str;
      default = [ "Mon-Fri *-*-* 07:00:00" ];
      description = ''
        systemd OnCalendar expressions. Weekday mornings: boards are refreshed
        on business days, and a run is idempotent, so extra firings are cheap.
      '';
    };
  };

  config = mkIf cfg.enable {
    users.users.${cfg.user} = {
      isSystemUser = true;
      group = cfg.group;
      description = "job-scraper service user";
    };
    users.groups.${cfg.group} = { };

    systemd.services.job-scraper = {
      description = "Scrape target-company job boards into the tracking sheet";
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      onFailure = [ "job-scraper-failure.service" ];
      serviceConfig = {
        Type = "oneshot";
        User = cfg.user;
        Group = cfg.group;
        EnvironmentFile = cfg.environmentFile;
        Environment = [ "GOOGLE_APPLICATION_CREDENTIALS=${cfg.googleCredentialsFile}" ];
        ExecStart = "${cfg.package}/bin/job-scraper --config ${configJson} scrape";
        StateDirectory = "job-scraper";
        StateDirectoryMode = "0700";
        ReadWritePaths = [ cfg.stateDir ];

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

    # The app reports its own board failures over ntfy. This catches the case it
    # cannot report: the run dying before it gets that far.
    systemd.services.job-scraper-failure = {
      description = "Notify that job-scraper.service failed";
      serviceConfig = {
        Type = "oneshot";
        User = cfg.user;
        Group = cfg.group;
        EnvironmentFile = cfg.environmentFile;
        NoNewPrivileges = true;
        PrivateTmp = true;
        ProtectSystem = "strict";
        ProtectHome = true;
      };
      script = ''
        ${pkgs.curl}/bin/curl -fsS \
          -H "Title: job-scraper failed" \
          -H "Priority: high" \
          -H "Tags: rotating_light" \
          -d "job-scraper.service failed on ${config.networking.hostName}. Check: journalctl -u job-scraper -n 50" \
          "${cfg.ntfyUrl}/$NTFY_TOPIC"
      '';
    };

    # Persist the dedup database. Without this, osgiliath's ephemeral root wipes
    # state.db on every boot and the next run re-appends every currently-open
    # posting to the sheet.
    #
    # Declared directly rather than through agindin.impermanence.systemDirectories
    # because that option is a plain list of paths and cannot carry ownership.
    # It has to: impermanence creates the backing directory under /persist and
    # bind-mounts it, and both ends come out root-owned.
    #
    # A tmpfiles rule is not enough on its own. systemd-tmpfiles-setup is
    # After=local-fs.target and the mount is WantedBy=local-fs.target, so the
    # rule does land correctly at boot -- but activation on a live deploy runs
    # tmpfiles before establishing the new mount, so the rule applies to the
    # directory the mount then hides, and the unit is left running as its own
    # user against a root-owned directory until the next reboot.
    # StateDirectory= does not re-own an existing mountpoint either.
    environment.persistence."/persist".directories = mkIf config.agindin.impermanence.enable [
      {
        directory = cfg.stateDir;
        user = cfg.user;
        group = cfg.group;
        mode = "0700";
      }
    ];

    systemd.timers.job-scraper = {
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = cfg.schedules;
        Persistent = true;
        RandomizedDelaySec = "10m";
        Unit = "job-scraper.service";
      };
    };
  };
}
