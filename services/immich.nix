{
  config,
  lib,
  unstablePkgs,
  globalVars,
  ...
}:

let
  cfg = config.agindin.services.immich;
  inherit (lib)
    mkIf
    mkEnableOption
    mkOption
    types
    ;
in
{
  options.agindin.services.immich = {
    enable = mkEnableOption "immich";

    mediaLocation = mkOption {
      type = types.path;
      default = /var/lib/immich/media;
      description = "Path where uploaded media will be stored.";
    };

    domain = mkOption {
      type = types.str;
      default = "immich.gindin.xyz";
    };
  };

  config = mkIf cfg.enable {
    services.immich = {
      enable = true;
      package = unstablePkgs.immich;
      mediaLocation = cfg.mediaLocation;
      host = "127.0.0.1";
      port = globalVars.ports.immich;
      environment = {
        IMMICH_METRICS = "true";
        IMMICH_TELEMETRY_INCLUDE = "all";
      };

      # Use upstream module's database management
      database = {
        enable = true;
        createDB = true;
        name = "immich";
        user = "immich";

        # Use VectorChord stack
        enableVectors = false;
        enableVectorChord = true;
      };

      redis.enable = true;
      machine-learning.enable = true;
    };

    # Fix permissions for Restic (recursive) and service UMask
    systemd = {
      services.immich-server.serviceConfig.UMask = lib.mkForce "0007";
      tmpfiles.rules = [
        "z ${cfg.mediaLocation} 0750 immich media - -"
      ];
    };

    # Ensure backup user exists (wrapper handles backup logic)
    agindin.services.postgres = {
      enable = true;
      ensureUsers = [ "immich" ];
    };

    # Allow Immich to access /media (if mediaLocation is there)
    users.users.immich = {
      isSystemUser = true;
      group = "immich";
      extraGroups = [ "media" ];
    };
    users.groups.immich = { };

    users.users.restic.extraGroups = mkIf config.agindin.services.restic.enable [ "immich" ];

    agindin.impermanence.systemDirectories = mkIf config.agindin.impermanence.enable [
      "/var/lib/immich"
      "/var/cache/immich" # Machine learning cache
    ];

    agindin.services.caddy.proxyHosts = mkIf config.agindin.services.caddy.enable [
      {
        domain = cfg.domain;
        port = globalVars.ports.immich;
      }
    ];

    agindin.services.restic.paths = mkIf config.agindin.services.restic.enable [
      cfg.mediaLocation
      "/var/lib/immich"
    ];
  };
}
