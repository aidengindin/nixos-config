{ config, lib, unstablePkgs, globalVars, ... }:
let
  cfg = config.agindin.services.pocket-id;
  inherit (lib) mkIf mkOption mkEnableOption types;

  dataDir = "/var/lib/pocket-id";
  uiPort = globalVars.ports.pocket-id.ui;
  prometheusPort = globalVars.ports.pocket-id.prometheus;
in {
  options.agindin.services.pocket-id = {
    enable = mkEnableOption "pocket-id";
    domain = mkOption {
      type = types.str;
      default = "auth.gindin.xyz";
    };
  };

  config = mkIf cfg.enable {
    age.secrets.pocket-id-encryption-key = {
      file = ../secrets/pocket-id-encryption-key.age;
      owner = "pocket-id";
      group = "pocket-id";
    };

    services.pocket-id = {
      enable = true;
      package = unstablePkgs.pocket-id;
      dataDir = "${dataDir}";
      settings = {
        APP_URL = "https://${cfg.domain}";
        PORT = uiPort;
        TRUST_PROXY = true;

        DB_CONNECTION_STRING = "postgresql://pocket-id@/pocket-id?host=/run/postgresql";

        ENCRYPTION_KEY_FILE = config.age.secrets.pocket-id-encryption-key.path;

        METRICS_ENABLED = true;
        OTEL_METRICS_EXPORTER = "prometheus";
        OTEL_EXPORTER_PROMETHEUS_PORT = prometheusPort;
      };
    };

    agindin.services.postgres = {
      enable = true;
      ensureUsers = [ "pocket-id" ];
    };

    agindin.services.caddy.proxyHosts = mkIf config.agindin.services.caddy.enable [{
      domain = cfg.domain;
      port = uiPort;
      extraConfig = ''
        header_up Host {host}
        header_up X-Real-IP {remote_host}
        header_up X-Forwarded-For {remote_host}
        header_up X-Forwarded-Proto {scheme}
        header_up X-Forwarded-Host {host}
      '';
    }];

    agindin.services.restic.paths = mkIf config.agindin.services.restic.enable [
      dataDir
    ];

    agindin.impermanence.systemDirectories = mkIf config.agindin.impermanence.enable [
      dataDir
    ];

    systemd.services.pocket-id-db-init = {
      description = "Intitialize Pocket ID database extensions";
      after = [ "postgresql.service" ];
      requires = [ "postgresql.service" ];
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        User = "postgres";
        Type = "oneshot";
        ExecStart = ''
          ${config.services.postgresql.package}/bin/psql -d pocket-id -c 'CREATE EXTENSION IF NOT EXISTS "uuid-ossp"; CREATE EXTENSION IF NOT EXISTS "pgcrypto";'
        '';
      };
    };

    systemd.services.pocket-id = {
      requires = [ "pocket-id-db-init.service" ];
      after = [ "pocket-id-db-init.service" ];
    };
  };
}

