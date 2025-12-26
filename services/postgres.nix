{ config, lib, pkgs, globalVars, ... }:
let
  cfg = config.agindin.services.postgres;
  inherit (lib) mkIf mkEnableOption mkOption types;

  mkUserList = users: map (user: { name = user; ensureDBOwnership = true; }) users;

  backupPath = "/var/backup/postgres";
in
{
  options.agindin.services.postgres = {
    enable = mkEnableOption "postgres";
    ensureUsers = mkOption {
      type = types.listOf types.str;
      default = [];
      description = "List of users for which to create Postgres users and associated databases";
    };
    backupTimerOnCalendar = mkOption {
      description = "systemd OnCalendar expression for backup frequency";
      type = types.str;
      default = "daily";
    };
  };

  config = mkIf cfg.enable {
    services.postgresql = {
      enable = true;
      ensureUsers = mkUserList cfg.ensureUsers;
      ensureDatabases = cfg.ensureUsers;
      settings.port = globalVars.ports.postgres;
    };

    agindin.impermanence.systemDirectories = mkIf config.agindin.impermanence.enable [
      "/var/lib/postgresql"
      backupPath
    ];

    agindin.services.restic.paths = mkIf config.agindin.services.restic.enable [
      backupPath
    ];

    systemd.services.postgres-backup = {
      description = "PostgreSQL backup";
      serviceConfig = {
        Type = "oneshot";
        User = "postgres";
        ExecStart = pkgs.writeShellScript "pg-backup" ''
          for db in ${lib.escapeShellArgs cfg.ensureUsers}; do
            ${config.services.postgresql.package}/bin/pg_dump -Fc "$db" \
              > "${backupPath}/$db.dump"
          done
        '';
      };
    };

    # To restore:
    # sudo -u postgres pg_restore -d mydb /var/backup/postgres/mydb.dump

    systemd.timers.postgres-backup = {
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = cfg.backupTimerOnCalendar;
        Persistent = true;
      };
    };
  };
}
