{
  config,
  lib,
  globalVars,
  ...
}:
let
  cfg = config.agindin.services.miniflux;
  inherit (lib)
    mkIf
    mkEnableOption
    mkOption
    types
    ;
in
{
  options.agindin.services.miniflux = {
    enable = mkEnableOption "miniflux";
    domain = mkOption {
      type = types.str;
      default = "rss.gindin.xyz";
    };

    oauth2ClientIdFile = mkOption {
      type = types.path;
      description = ''
        File containing client ID configured in OIDC provider.
        Should be owned by root.
      '';
    };
    oauth2ClientSecretFile = mkOption {
      type = types.path;
      description = ''
        File containing client secret configured in OIDC provider.
        Should be owned by root.
      '';
    };
    oidcHost = mkOption {
      type = types.str;
      default = "auth.gindin.xyz";
      description = "Host of OIDC provider";
    };
  };

  config = mkIf cfg.enable {
    assertions = [
      {
        assertion = config.services.postgresql.enable;
        message = "Miniflux requires PostgreSQL to be enabled";
      }
    ];

    agindin.services.postgres.ensureUsers = [ "miniflux" ];

    services.miniflux = {
      enable = true;
      config = {
        PORT = globalVars.ports.miniflux;
        CREATE_ADMIN = 0;
        OAUTH2_PROVIDER = "oidc";
        OAUTH2_CLIENT_ID_FILE = "/run/credentials/miniflux.service/client_id";
        OAUTH2_CLIENT_SECRET_FILE = "/run/credentials/miniflux.service/client_secret";
        OAUTH2_REDIRECT_URL = "https://${cfg.domain}/oauth2/oidc/callback";
        OAUTH2_OIDC_DISCOVERY_ENDPOINT = "https://${cfg.oidcHost}";
        OAUTH2_OIDC_PROVIDER_NAME = "PocketID";
        OAUTH2_USER_CREATION = 1;
        DISABLE_LOCAL_AUTH = 1;
        LOG_LEVEL = "info";
        METRICS_COLLECTOR = "1";
        METRICS_ALLOWED_NETWORKS = "127.0.0.1/32,100.0.0.0/8";
      };
    };

    networking.firewall.interfaces.tailscale0.allowedTCPPorts = [ globalVars.ports.miniflux ];

    systemd.services.miniflux.serviceConfig.LoadCredential = [
      "client_id:${cfg.oauth2ClientIdFile}"
      "client_secret:${cfg.oauth2ClientSecretFile}"
    ];

    agindin.services.caddy.proxyHosts = mkIf config.agindin.services.caddy.enable [
      {
        domain = cfg.domain;
        port = globalVars.ports.miniflux;
      }
    ];
  };
}
