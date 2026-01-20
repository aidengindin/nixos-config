{
  config,
  lib,
  pkgs,
  globalVars,
  ...
}:
let
  cfg = config.agindin.services.openwebui;
  inherit (lib)
    mkIf
    mkEnableOption
    mkOption
    types
    ;

  # Override open-webui to include PostgreSQL driver
  open-webui-with-postgres = pkgs.open-webui.overridePythonAttrs (old: {
    propagatedBuildInputs = (old.propagatedBuildInputs or [ ]) ++ [
      pkgs.python3Packages.psycopg2
    ];
  });
in
{
  options.agindin.services.openwebui = {
    enable = mkEnableOption "openwebui";
    domain = mkOption {
      type = types.str;
      default = "openwebui.gindin.xyz";
    };
  };

  config = mkIf cfg.enable {
    age.secrets = {
      openwebui-env.file = ../secrets/openwebui-env.age;
    };

    agindin.services.postgres = {
      enable = true;
      ensureUsers = [ "open-webui" ];
      extensions = [ (ps: [ ps.pgvector ]) ];
    };

    systemd.services.openwebui-init-db = {
      description = "Initialize open-webui database with pgvector extension";
      after = [
        "postgresql.service"
        "postgresql-ensure-databases.service"
      ];
      before = [ "open-webui.service" ];
      requires = [ "postgresql.service" ];
      wantedBy = [ "open-webui.service" ];

      serviceConfig = {
        Type = "oneshot";
        User = "postgres";
        RemainAfterExit = true;
      };

      script = ''
        ${config.services.postgresql.package}/bin/psql -d open-webui \
          -c 'CREATE EXTENSION IF NOT EXISTS vector;'
      '';
    };

    services.open-webui = {
      enable = true;
      package = open-webui-with-postgres;
      port = globalVars.ports.open-webui;
      environment = {
        BYPASS_MODEL_ACCESS_CONTROL = "true";
        WEBUI_URL = "https://${cfg.domain}";
        DATABASE_URL = "postgresql:///open-webui?host=/run/postgresql";
        DATABASE_ENABLE_SESSION_SHARING = "true";
        PGVECTOR_CREATE_EXTENSION = "false";
      };
      environmentFile = config.age.secrets.openwebui-env.path;
    };

    agindin.services.caddy.proxyHosts = mkIf config.agindin.services.caddy.enable [
      {
        domain = cfg.domain;
        port = globalVars.ports.open-webui;
      }
    ];

    agindin.impermanence.systemDirectories = mkIf config.agindin.impermanence.enable [
      config.services.open-webui.stateDir
    ];
  };
}
