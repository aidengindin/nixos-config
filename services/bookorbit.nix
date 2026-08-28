{
  config,
  lib,
  globalVars,
  ...
}:
let
  cfg = config.agindin.services.bookorbit;
  inherit (lib)
    mkIf
    mkEnableOption
    mkOption
    types
    ;

  dataDir = "/var/lib/bookorbit";
  backupPath = "/var/backup/bookorbit";

  # User-defined docker network so the app can reach the DB by container name.
  # The DB publishes no host port; it is only reachable from this network.
  network = "bookorbit";

  containerPort = 3000;
in
{
  options.agindin.services.bookorbit = {
    enable = mkEnableOption "BookOrbit ebook/audiobook library server";

    domain = mkOption {
      type = types.str;
      default = "books.gindin.xyz";
      description = "Domain name for the BookOrbit instance.";
    };

    libraryPath = mkOption {
      type = types.str;
      default = "/media/books";
      description = ''
        Host path holding the book files, mounted at /books in the container.
        Point BookOrbit's library at /books when creating it in the UI.
      '';
    };

    dockPath = mkOption {
      type = types.str;
      default = "/media/book-dock";
      description = ''
        Host path for the Book Dock drop folder, mounted at /dock. Files landing
        here are picked up and imported automatically. This is where
        `agindin.services.acsm` writes fulfilled, DRM-free books.

        Kept on the same filesystem as `libraryPath` so imports are renames
        rather than copies.
      '';
    };

    environmentFile = mkOption {
      type = types.path;
      default = ../secrets/bookorbit-env.age;
      description = ''
        Age-encrypted env file supplying the secrets BookOrbit requires:
        POSTGRES_PASSWORD, JWT_SECRET, SETUP_BOOTSTRAP_TOKEN, and (recommended)
        EMAIL_ENCRYPTION_KEY and MIGRATION_ENCRYPTION_KEY.
      '';
    };

    appImage = mkOption {
      type = types.str;
      default = "ghcr.io/bookorbit/bookorbit:latest";
      description = "BookOrbit application image.";
    };

    dbImage = mkOption {
      type = types.str;
      # Upstream's docker-compose.yml pins this; BookOrbit needs pgvector
      # alongside uuid-ossp and pg_trgm.
      default = "pgvector/pgvector:pg18";
      description = "PostgreSQL image for BookOrbit's database.";
    };

    allowLocalOidcIssuers = mkOption {
      type = types.bool;
      default = false;
      description = ''
        Let the OIDC issuer resolve to a private address. BookOrbit runs issuer
        and endpoint URLs through an SSRF guard that rejects RFC1918, loopback,
        link-local and CGNAT ranges — and Tailscale's 100.64.0.0/10 is in that
        last one, so an issuer on the tailnet needs this.
      '';
    };

    migrationImportPath = mkOption {
      type = types.nullOr types.str;
      default = null;
      example = "/var/lib/bookorbit/imports";
      description = ''
        Optional host directory mounted read-only at /imports, holding the
        `cwa/{app.db,metadata.db}` snapshots for the one-time Calibre-Web
        Automated import. Leave null once the migration is done.
      '';
    };

    backupTimerOnCalendar = mkOption {
      type = types.str;
      default = "daily";
      description = "systemd OnCalendar expression for the pg_dump backup job.";
    };
  };

  config = mkIf cfg.enable {
    age.secrets.bookorbit-env = {
      file = cfg.environmentFile;
      # Read by dockerd (root) when starting the containers.
      mode = "0400";
    };

    # `virtualisation.oci-containers` has no notion of networks, so create it
    # once before either container starts.
    systemd.services.bookorbit-network = {
      description = "Create the BookOrbit docker network";
      after = [ "docker.service" ];
      requires = [ "docker.service" ];
      wantedBy = [ "multi-user.target" ];
      path = [ config.virtualisation.docker.package ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      script = ''
        docker network inspect ${network} > /dev/null 2>&1 \
          || docker network create ${network}
      '';
    };

    virtualisation.oci-containers.containers = {
      bookorbit-db = {
        image = cfg.dbImage;
        environment = {
          POSTGRES_USER = "bookorbit";
          POSTGRES_DB = "bookorbit";
          PGDATA = "/var/lib/postgresql/data/pgdata";
        };
        environmentFiles = [ config.age.secrets.bookorbit-env.path ];
        volumes = [ "${dataDir}/postgres:/var/lib/postgresql/data" ];
        extraOptions = [ "--network=${network}" ];
      };

      bookorbit = {
        image = cfg.appImage;
        dependsOn = [ "bookorbit-db" ];
        environment = {
          NODE_ENV = "production";
          PORT = toString containerPort;
          TZ = "America/New_York";
          PUID = "1000";
          PGID = toString config.users.groups.media.gid;

          POSTGRES_HOST = "bookorbit-db";
          POSTGRES_PORT = "5432";
          POSTGRES_USER = "bookorbit";
          POSTGRES_DB = "bookorbit";

          APP_URL = "https://${cfg.domain}";
          # Hides the rest of the container root from the library folder picker.
          LIBRARY_BROWSE_ROOT = "/books";
          BOOK_DOCK_PATH = "/dock";

          OIDC_ALLOW_LOCAL_ISSUERS = lib.boolToString cfg.allowLocalOidcIssuers;
        }
        // lib.optionalAttrs (cfg.migrationImportPath != null) {
          MIGRATION_IMPORT_ROOT = "/imports";
        };
        environmentFiles = [ config.age.secrets.bookorbit-env.path ];
        volumes = [
          "${cfg.libraryPath}:/books"
          "${cfg.dockPath}:/dock"
          "${dataDir}/app:/data"
        ]
        ++ lib.optional (cfg.migrationImportPath != null) "${cfg.migrationImportPath}:/imports:ro";
        ports = [ "127.0.0.1:${toString globalVars.ports.bookorbit}:${toString containerPort}" ];
        # Mirrors the hardening in upstream's docker-compose.yml.
        extraOptions = [
          "--network=${network}"
          "--init"
          "--read-only"
          "--tmpfs=/tmp"
          "--cap-drop=ALL"
          "--cap-add=CHOWN"
          "--cap-add=DAC_OVERRIDE"
          "--cap-add=FOWNER"
          "--cap-add=SETGID"
          "--cap-add=SETUID"
          "--security-opt=no-new-privileges:true"
        ];
      };
    };

    systemd.services = {
      docker-bookorbit-db = {
        after = [ "bookorbit-network.service" ];
        requires = [ "bookorbit-network.service" ];
      };
      docker-bookorbit = {
        after = [ "bookorbit-network.service" ];
        requires = [ "bookorbit-network.service" ];
      };

      # The DB lives in a container, so it is outside services/postgres.nix's
      # backup loop; dump it the same way and let restic pick up the dump.
      bookorbit-db-backup = {
        description = "BookOrbit database backup";
        after = [ "docker-bookorbit-db.service" ];
        requires = [ "docker-bookorbit-db.service" ];
        path = [ config.virtualisation.docker.package ];
        serviceConfig = {
          Type = "oneshot";
          NoNewPrivileges = true;
          PrivateTmp = true;
          ProtectHome = true;
          ProtectSystem = "strict";
          ReadWritePaths = [ backupPath ];
        };
        script = ''
          docker exec bookorbit-db pg_dump -U bookorbit -Fc bookorbit \
            > "${backupPath}/bookorbit.dump.tmp"
          mv "${backupPath}/bookorbit.dump.tmp" "${backupPath}/bookorbit.dump"
        '';
      };
    };

    systemd.timers.bookorbit-db-backup = {
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = cfg.backupTimerOnCalendar;
        Persistent = true;
      };
    };

    systemd.tmpfiles.rules = [
      "d ${dataDir} 0750 root root -"
      "d ${dataDir}/app 0750 1000 ${toString config.users.groups.media.gid} -"
      "d ${dataDir}/postgres 0700 root root -"
      "d ${backupPath} 0750 root root -"
      "d ${cfg.dockPath} 0775 1000 ${toString config.users.groups.media.gid} -"
    ]
    ++ lib.optional (
      cfg.migrationImportPath != null
    ) "d ${cfg.migrationImportPath} 0700 1000 ${toString config.users.groups.media.gid} -";

    agindin.services.caddy.proxyHosts = mkIf config.agindin.services.caddy.enable [
      {
        domain = cfg.domain;
        port = globalVars.ports.bookorbit;
        extraConfig = ''
          header_up Host {host}
          header_up X-Real-IP {remote_host}
          header_up X-Forwarded-For {remote_host}
          header_up X-Forwarded-Proto {scheme}
          header_up X-Forwarded-Host {host}
        '';
      }
    ];

    agindin.services.restic.paths = mkIf config.agindin.services.restic.enable [
      "${dataDir}/app"
      backupPath
    ];

    agindin.impermanence.systemDirectories = mkIf config.agindin.impermanence.enable [
      dataDir
      backupPath
    ];
  };
}
