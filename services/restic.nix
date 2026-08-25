{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.agindin.services.restic;
  inherit (lib)
    mkIf
    mkEnableOption
    mkOption
    types
    ;

  # The setfacl grants in resticPermissions below are not sufficient on their
  # own. A chmod on a file carrying a POSIX ACL recalculates the ACL mask from
  # the group permission bits, so any service that hardens its own state
  # directory silently revokes restic's access: hermes-agent chmods
  # $HERMES_HOME/cron to 0700 whenever it writes a cron job, which drops the
  # mask to --- and leaves `user:restic:r-x #effective:---`. Each deploy
  # re-granted it and the next write took it away again, so restic exited 3 on
  # every run from 2026-08-08 and the unit sat permanently failed — which in
  # turn kept the systemd-failed alert firing and taught us to ignore it.
  #
  # CAP_DAC_READ_SEARCH is the capability made for this: it bypasses file read
  # and directory search permission checks without running the backup as root,
  # and it fixes the whole class rather than one directory. Already present in
  # the units' CapabilityBoundingSet, so it only needs raising into the
  # ambient set.
  #
  # The trade-off is real: the restic user can now read any file on the host.
  # It already read every backed-up path wholesale — including agenix-derived
  # material under the service state directories it snapshots — so this widens
  # reach rather than introducing a new class of exposure, but it does widen it.
  backupReadCapability = [ "CAP_DAC_READ_SEARCH" ];
in
{
  options.agindin.services.restic = {
    enable = mkEnableOption "restic";
    paths = mkOption {
      type = types.listOf types.str;
      default = [ ];
      description = "Paths to back up";
    };
    localBackup = {
      enable = mkEnableOption "restic local backup";
      repository = mkOption {
        type = types.str;
        description = "Path to local backup directory";
      };
      repositoryMountUnitName = mkOption {
        type = types.str;
        description = "Systemd mount unit name for the device containing the local repository (if applicable)";
        default = "";
      };
    };
    b2Backup = {
      enable = mkEnableOption "restic b2 backup";
      bucket = mkOption {
        type = types.str;
        description = "Name of the B2 bucket";
      };
      environmentFile = mkOption {
        type = types.path;
        description = "Path to file containing B2_ACCOUNT_ID and B2_ACCOUNT_KEY";
      };
    };
    passwordPath = mkOption {
      type = types.path;
      description = "Path to password file";
    };
  };

  config = mkIf cfg.enable {
    environment.systemPackages = with pkgs; [ acl ];

    users.users.restic = {
      isSystemUser = true;
      group = "restic";
      extraGroups = [
        "postgres"
      ]
      ++ lib.optional (config.users.groups ? keys) config.users.groups.keys.name;
      description = "Restic backup service user";
      home = "/var/lib/restic";
      createHome = true;
      openssh.authorizedKeys.keys = [ ];
    };
    users.groups.restic = { };

    system.activationScripts = {

      # generate an ssh key for the restic user
      resticSshKey = ''
        if [ ! -e /var/lib/restic/.ssh/id_ed25519 ]; then
          mkdir -p /var/lib/restic/.ssh
          ${pkgs.openssh}/bin/ssh-keygen -t ed25519 -f /var/lib/restic/.ssh/id_ed25519 -q -N ""
          chown -R restic:restic /var/lib/restic/.ssh
          chmod 700 /var/lib/restic/.ssh
          chmod 600 /var/lib/restic/.ssh/id_ed25519
        fi
      '';

      # grant the restic user access to any directories it's backing up
      resticPermissions = ''
        ${lib.concatMapStrings (path: ''
          ${pkgs.acl}/bin/setfacl -R -m u:restic:rX ${path}
          ${pkgs.acl}/bin/setfacl -R -dm u:restic:rX ${path}
        '') cfg.paths}
      '';
    };

    systemd = {
      tmpfiles.rules = lib.optionals cfg.localBackup.enable [
        "d ${cfg.localBackup.repository} 0750 restic restic - -"
      ];
      services."restic-backups-local" = {
        serviceConfig = {
          CPUQuota = "50%";
          Nice = 19;
          IOSchedulingClass = "idle";
          SupplementaryGroups = config.users.users.restic.extraGroups;
          AmbientCapabilities = backupReadCapability;
        };
        after = mkIf (cfg.localBackup.repositoryMountUnitName != "") [
          cfg.localBackup.repositoryMountUnitName
        ];
        requires = mkIf (cfg.localBackup.repositoryMountUnitName != "") [
          cfg.localBackup.repositoryMountUnitName
        ];
      };
      services."restic-backups-b2" = mkIf cfg.b2Backup.enable {
        serviceConfig = {
          SupplementaryGroups = config.users.users.restic.extraGroups;
          AmbientCapabilities = backupReadCapability;
        };
      };
    };

    services.restic = {
      backups =
        let
          commonOptions = {
            initialize = true;
            passwordFile = "${cfg.passwordPath}";
            paths = cfg.paths;
            pruneOpts = [
              "--keep-daily 7"
              "--keep-weekly 4"
              "--keep-monthly 12"
            ];
            timerConfig = {
              OnCalendar = "02:00";
              Persistent = true;
              OnClockChange = true;
              OnTimezoneChange = true;
            };
            user = "restic";
          };
        in
        {
          local = mkIf cfg.localBackup.enable (
            commonOptions
            // {
              repository = cfg.localBackup.repository;
            }
          );
          b2 = mkIf cfg.b2Backup.enable (
            commonOptions
            // {
              repository = "b2:${cfg.b2Backup.bucket}";
              environmentFile = cfg.b2Backup.environmentFile;
            }
          );
        };
    };
  };
}
