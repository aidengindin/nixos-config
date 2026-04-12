{
  config,
  lib,
  globalVars,
  ...
}:
let
  cfg = config.agindin.services.liftosaur-sync;
  inherit (lib)
    mkIf
    mkEnableOption
    mkOption
    types
    ;
in
{
  options.agindin.services.liftosaur-sync = {
    enable = mkEnableOption "liftosaur-sync workout sync server";
    domain = mkOption {
      type = types.str;
      default = "liftosaur-sync.gindin.xyz";
    };
    environmentFile = mkOption {
      type = types.path;
      description = "Path to the age-decrypted environment file containing API secrets (LIFTOSAUR_API_KEY, INTERVALS_API_KEY, STRAVA_CLIENT_ID, etc.).";
    };
    syncIntervals = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = "systemd calendar expression for periodic sync (e.g. \"hourly\" or \"*:0/30\"). null disables the timer.";
    };
  };

  config = mkIf cfg.enable {
    services.liftosaur-sync = {
      enable = true;
      port = globalVars.ports.liftosaur-sync;
      baseUrl = "https://${cfg.domain}";
      environmentFile = cfg.environmentFile;
      syncIntervals = cfg.syncIntervals;
    };

    agindin.services.caddy.proxyHosts = mkIf config.agindin.services.caddy.enable [
      {
        domain = cfg.domain;
        port = globalVars.ports.liftosaur-sync;
      }
    ];

    agindin.services.restic.paths = mkIf config.agindin.services.restic.enable [
      "/var/lib/liftosaur-sync"
    ];

    agindin.impermanence.systemDirectories = mkIf config.agindin.impermanence.enable [
      "/var/lib/liftosaur-sync"
    ];
  };
}
