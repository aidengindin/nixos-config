{ config, lib, pkgs, unstablePkgs, ... }:
let
  cfg = config.agindin.services.withings-sync;
  inherit (lib) mkIf mkEnableOption mkOption types mapAttrs' nameValuePair concatStringsSep;

  withingsPackage = unstablePkgs.python312Packages.withings-sync.overrideAttrs (oldAttrs: {
    src = pkgs.fetchFromGitHub {
      owner = "aidengindin";
      repo = "withings-sync";
      rev = "feat/credential-file-env-variable";
      sha256 = "sha256-bwaRp573ccMFHdA6N8n6hUI20hDPce17b3U8rGmhk4w=";
    };
    propagatedBuildInputs = (oldAttrs.propagatedBuildInputs or []) ++ [
      unstablePkgs.python312Packages.setuptools
    ];
  });

  syncOpts = { name, config, ... }: {
    options = {
      enable = mkEnableOption "withings-sync service for ${name}";

      garminCredentials = {
        username = mkOption {
          type = types.str;
          description = "Garmin Connect username";
        };
        passwordFile = mkOption {
          type = types.path;
          description = "Path to a file containing the Garmin Connect password";
        };
      };

      stateDir = mkOption {
        type = types.path;
        default = "/var/lib/withings-sync/${name}";
        description = "Directory to store state in";
      };

      features = mkOption {
        type = types.listOf types.str;
        default = [];
        description = "List of features to enable (e.g. BLOOD_PRESSURE)";
        example = [ "BLOOD_PRESSURE" ];
      };

      interval = mkOption {
        type = types.str;
        default = "1h";
        description = "Systemd timer interval to run the sync";
      };

      extraArgs = mkOption {
        type = types.listOf types.str;
        default = [];
        description = "Extra arguments to pass to the sync script";
      };

      user = mkOption {
        type = types.str;
        description = "User to run the sync script as";
      };

      group = mkOption {
        type = types.str;
        description = "Group to run the sync script as";
      };
    };
  };
in
{
  options.agindin.services.withings-sync = {
    enable = mkEnableOption "withings-sync";
    users = mkOption {
      type = types.attrsOf (types.submodule syncOpts);
      default = {};
      description = "Sync configuration for each user";
    };
    package = mkOption {
      type = types.package;
      default = withingsPackage;
      description = "Nix package to use for withings-sync";
    };
  };

  config = mkIf cfg.enable {
    environment.systemPackages = [
      cfg.package
    ];

    systemd.tmpfiles.rules = lib.concatLists (lib.mapAttrsToList (name: userCfg: [
      ''
        d ${userCfg.stateDir}/config 0700 ${userCfg.user} ${userCfg.group} -
      ''
    ]) cfg.users);

    systemd.services = mapAttrs' (name: userCfg:
      nameValuePair "withings-sync-${name}" {
        description = "Withings sync for ${name}";
        wantedBy = [ "multi-user.target" ];
        after = [ "network-online.target" ];
        requires = [ "network-online.target" ];
        path = [ cfg.package ];
        serviceConfig = {
          Type = "oneshot";
          User = userCfg.user;
          Group = userCfg.group;
          WorkingDirectory = userCfg.stateDir;
          StateDirectory = baseNameOf userCfg.stateDir;
          StateDirectoryMode = "0700";

          # Security hardening
          CapabilityBoundingSet = "";
          LockPersonality = true;
          MemoryDenyWriteExecute = true;
          NoNewPrivileges = true;
          PrivateDevices = true;
          PrivateTmp = true;
          ProtectClock = true;
          ProtectControlGroups = true;
          ProtectHome = true;
          ProtectHostname = true;
          ProtectKernelLogs = true;
          ProtectKernelModules = true;
          ProtectKernelTunables = true;
          ProtectSystem = "strict";
          ReadWritePaths = [ userCfg.stateDir ];
          RemoveIPC = true;
          RestrictNamespaces = true;
          RestrictRealtime = true;
          RestrictSUIDSGID = true;
          SystemCallArchitectures = "native";
          SystemCallFilter = [ "@system-service" "~@resources" "~@privileged" ];
          UMask = "0077";
        };

        script = let
          featuresArg = if userCfg.features != []
            then "--features ${concatStringsSep "," userCfg.features}"
            else "";
        in ''
          set -euo pipefail

          export HOME="${userCfg.stateDir}"

          export GARMIN_PASSWORD_FILE="${userCfg.garminCredentials.passwordFile}"

          withings-sync \
            --garmin-username "${userCfg.garminCredentials.username}" \
            ${featuresArg} \
            ${concatStringsSep " " userCfg.extraArgs}
        '';
      }
    ) cfg.users;

    systemd.timers = mapAttrs' (name: userCfg:
      nameValuePair "withings-sync-${name}.timer" {
        description = "Withings sync for ${name}";
        wantedBy = [ "timers.target" ];
        timerConfig = {
          OnBootSec = "5m";
          OnUnitActiveSec = userCfg.interval;
          RandomizedDelaySec = "5m";
          Unit = "withings-sync-${name}.service";
        };
      }
    ) cfg.users;
  };
}
