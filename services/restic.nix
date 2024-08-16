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
      repositoryFile = mkOption {
        type = types.path;
        description = "Path to local backup file";
      };
    };
    passwordPath = mkOption {
      type = types.path;
      description = "Path to password file";
    };
  };

  config = mkIf cfg.enable {
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
      };
    in {
      local = mkIf cfg.localBackup.enable (commonOptions // {
        repositoryFile = cfg.localBackup.repositoryFile;
      });
    };
  };
}
