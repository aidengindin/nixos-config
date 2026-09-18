{
  config,
  lib,
  globalVars,
  ...
}:
let
  cfg = config.agindin.services.firefly-iii;
  inherit (lib)
    mkIf
    mkEnableOption
    mkOption
    types
    ;

  # Mirrors upstream's systemd.tmpfiles.settings."10-firefly-iii" and
  # ."10-firefly-iii-data-importer". See the StateDirectory comment below for
  # why these are restated here.
  fireflyDirs = [
    "storage"
    "storage/app"
    "storage/database"
    "storage/export"
    "storage/framework"
    "storage/framework/cache"
    "storage/framework/sessions"
    "storage/framework/views"
    "storage/logs"
    "storage/upload"
    "cache"
  ];

  importerDirs = [
    "storage"
    "storage/app"
    "storage/app/public"
    "storage/configurations"
    "storage/conversion-routines"
    "storage/debugbar"
    "storage/framework"
    "storage/framework/cache"
    "storage/framework/sessions"
    "storage/framework/testing"
    "storage/framework/views"
    "storage/import-jobs"
    "storage/jobs"
    "storage/logs"
    "storage/submission-routines"
    "storage/uploads"
    "cache"
  ];

  stateDirs = base: dirs: lib.concatStringsSep " " ([ base ] ++ map (d: "${base}/${d}") dirs);

  # Both setup units are RemainAfterExit oneshots that bake the environment
  # into Laravel's config cache, and upstream keys their restartTriggers only
  # on the package. The maintenance script embeds the secret's *runtime* path
  # rather than its contents, so rotating a secret changes nothing systemd can
  # see: the unit doesn't re-run, config:cache keeps the old value, and the
  # importer reports "Firefly III refused the connection" with a perfectly good
  # token on disk. Mapping the runtime path back to the .age ciphertext in the
  # store gives us something that *does* change when the secret is re-encrypted.
  ageSourceOf =
    runtimePath:
    map (secret: secret.file) (
      lib.filter (secret: secret.path == runtimePath) (lib.attrValues config.age.secrets)
    );

  # Both apps are Laravel, so the Caddyfile is identical apart from which
  # package and which php-fpm socket. php_fastcgi already does the
  # try_files/index.php rewrite Laravel wants, so there's nothing to add.
  laravelSite = package: socket: ''
    root * ${package}/public
    encode gzip
    php_fastcgi unix/${socket}
    file_server
  '';
in
{
  options.agindin.services.firefly-iii = {
    enable = mkEnableOption "firefly-iii";

    domain = mkOption {
      type = types.str;
      default = "money.gindin.xyz";
    };

    importerDomain = mkOption {
      type = types.str;
      default = "money-import.gindin.xyz";
      description = "Domain for the Firefly III Data Importer, used for CSV/OFX imports.";
    };

    appKeyFile = mkOption {
      type = types.path;
      description = ''
        File containing Firefly III's 32-character app key. Generate with:
        echo "base64:$(head -c 32 /dev/urandom | base64)"

        Unlike the services that use LoadCredential, upstream's maintenance
        script reads this file directly as the service user, so it must be
        owned by `firefly-iii` rather than root.
      '';
    };

    importerAccessTokenFile = mkOption {
      type = types.path;
      description = ''
        File containing a Firefly III Personal Access Token for the data
        importer. This can only be minted from the Firefly III UI once an
        account exists, so the first deploy of this service necessarily runs
        with a placeholder.

        Read directly by the service user, so it must be owned by
        `firefly-iii-data-importer`.
      '';
    };
  };

  config = mkIf cfg.enable {
    assertions = [
      {
        assertion = config.services.postgresql.enable;
        message = "Firefly III requires PostgreSQL to be enabled";
      }
    ];

    # Nothing here closes registration: Firefly's single_user_mode defaults to
    # true and is stored in the database, so once the shared household account
    # is registered no further accounts can be created. It's toggled from
    # Administration -> Configuration, not from the environment.

    # services/postgres.nix creates the role with ensureDBOwnership, so the
    # database name has to equal the role name, and both have to equal the OS
    # user php-fpm runs as for peer auth over the socket to work.
    agindin.services.postgres.ensureUsers = [ "firefly-iii" ];

    services.firefly-iii = {
      enable = true;
      enableNginx = false;
      # The php-fpm pool sets listen.owner/listen.group from this, and Caddy
      # has to be in that group to reach the socket.
      group = "caddy";
      virtualHost = cfg.domain;
      settings = {
        APP_ENV = "local";
        APP_KEY_FILE = cfg.appKeyFile;
        SITE_OWNER = "aiden@aidengindin.com";
        TZ = "America/New_York";
        DB_CONNECTION = "pgsql";
        DB_HOST = "/run/postgresql";
        DB_PORT = globalVars.ports.postgres;
        DB_DATABASE = "firefly-iii";
        DB_USERNAME = "firefly-iii";
      };
    };

    services.firefly-iii-data-importer = {
      enable = true;
      enableNginx = false;
      group = "caddy";
      virtualHost = cfg.importerDomain;
      settings = {
        APP_ENV = "local";
        TZ = "America/New_York";
        FIREFLY_III_ACCESS_TOKEN_FILE = cfg.importerAccessTokenFile;
        # URL the importer talks to server-side, and the one it sends the
        # browser to. Same host either way; both apps are on the tailnet.
        FIREFLY_III_URL = "https://${cfg.domain}";
        VANITY_URL = "https://${cfg.domain}";
      };
    };

    # No entry in common/variables.nix, unlike every other service here: both
    # apps are php-fpm behind Unix sockets, so there's no TCP port to allocate
    # and nothing to open in the firewall.
    agindin.services.caddy.extraSites = mkIf config.agindin.services.caddy.enable [
      {
        domain = cfg.domain;
        config = laravelSite config.services.firefly-iii.package config.services.phpfpm.pools.firefly-iii.socket;
      }
      {
        domain = cfg.importerDomain;
        config = laravelSite config.services.firefly-iii-data-importer.package config.services.phpfpm.pools.firefly-iii-data-importer.socket;
      }
    ];

    # Upstream sets StateDirectory=firefly-iii, but only the top-level dir; the
    # whole storage/ tree underneath comes from systemd.tmpfiles, which races
    # the impermanence bind mount. When the mount wins, tmpfiles populates the
    # now-hidden directory underneath and the mounted one comes up empty, so
    # the first artisan call dies on a FilesystemException — the *arr failure
    # mode again, one level deeper than StateDirectory reaches. Restating every
    # subdirectory here creates them at unit start, after the mount.
    #
    # mkForce because upstream already defines StateDirectory on these units.
    systemd.services = {
      firefly-iii-setup = {
        serviceConfig.StateDirectory = lib.mkForce (stateDirs "firefly-iii" fireflyDirs);
        restartTriggers = ageSourceOf cfg.appKeyFile;
      };
      firefly-iii-data-importer-setup = {
        serviceConfig.StateDirectory = lib.mkForce (stateDirs "firefly-iii-data-importer" importerDirs);
        restartTriggers = ageSourceOf cfg.importerAccessTokenFile;
      };
    };

    agindin.impermanence.systemDirectories = mkIf config.agindin.impermanence.enable [
      "/var/lib/firefly-iii"
      "/var/lib/firefly-iii-data-importer"
    ];

    # The database itself rides the nightly pg_dump that services/postgres.nix
    # already hands to restic; this covers uploaded attachments.
    agindin.services.restic.paths = mkIf config.agindin.services.restic.enable [
      "/var/lib/firefly-iii"
    ];
  };
}
