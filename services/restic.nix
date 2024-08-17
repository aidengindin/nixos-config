{ config, lib, pkgs, ... }:
let
  cfg = config.agindin.services.restic;
  inherit (lib) mkIf mkEnableOption mkOption types;
in
{
  options.agindin.services.restic = {
    enable = mkEnableOption "restic";
    paths = mkOption {
      type = types.listOf types.str;
      default = [];
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
      description = "Restic backup service user";
      home = "/var/lib/restic";
      createHome = true;
      openssh.authorizedKeys.keys = [];
    };
    users.groups.restic = {};

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
        serviceConfig.SupplementaryGroups = [ config.users.groups.keys.name ];
      } // mkIf (cfg.localBackup.repositoryMountUnitName != "") {
        after = [ cfg.localBackup.repositoryMountUnitName ];
        requires = [ cfg.localBackup.repositoryMountUnitName ];
      };
    };

    services.restic.backups = let
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
          OnCalendar = "daily";
          Persistent = true;
          OnClockChange = true;
          OnTimezoneChange = true;
        };
        user = "restic";
      };
    in {
      local = mkIf cfg.localBackup.enable (commonOptions // {
        repository = cfg.localBackup.repository;
      });
    };
  };
}
