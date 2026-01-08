{
  config,
  lib,
  globalVars,
  ...
}:
let
  cfg = config.agindin.services.linkwarden;
  inherit (lib)
    mkIf
    mkEnableOption
    mkOption
    types
    ;

  dataDir = "/var/lib/linkwarden";
in
{
  options.agindin.services.linkwarden = {
    enable = mkEnableOption "Whether to enable Linkwarden.";
    domain = mkOption {
      type = types.str;
      default = "links.gindin.xyz";
    };

    oauth2ClientIdFile = mkOption {
      type = types.path;
      description = "File containing client ID configured in OIDC provider";
      default = ../secrets/linkwarden-client-id.age;
    };
    oauth2ClientSecretFile = mkOption {
      type = types.path;
      description = "File containing client secret configured in OIDC provider";
      default = ../secrets/linkwarden-client-secret.age;
    };
    nextAuthSecretFile = mkOption {
      type = types.path;
      description = "File containing NextAuth secret";
      default = ../secrets/linkwarden-nextauth-secret.age;
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
        message = "Linkwarden requires PostgreSQL to be enabled";
      }
    ];

    agindin.services.postgres.ensureUsers = [ "linkwarden" ];

    age.secrets = {
      linkwardenClientId = {
        file = cfg.oauth2ClientIdFile;
        owner = "linkwarden";
        group = "linkwarden";
        mode = "0440";
      };
      linkwardenClientSecret = {
        file = cfg.oauth2ClientSecretFile;
        owner = "linkwarden";
        group = "linkwarden";
        mode = "0440";
      };
      linkwardenNextAuthSecret = {
        file = cfg.nextAuthSecretFile;
        owner = "linkwarden";
        group = "linkwarden";
        mode = "0440";
      };
    };

    services.linkwarden = {
      enable = true;
      storageLocation = dataDir;
      port = globalVars.ports.linkwarden;
      database.host = "/run/postgresql";

      environment = {
        NEXT_PUBLIC_DISABLE_REGISTRATION = "true";
        NEXT_PUBLIC_AUTHENTIK_ENABLED = "true";
        AUTHENTIK_ISSUER = "https://${cfg.oidcHost}";
        AUTHENTIK_CUSTOM_NAME = "Pocket ID";
        # Linkwarden requires NEXTAUTH_URL to be set if not localhost
        NEXTAUTH_URL = "https://${cfg.domain}/api/v1/auth";
      };

      secretFiles = {
        "AUTHENTIK_CLIENT_ID" = config.age.secrets.linkwardenClientId.path;
        "AUTHENTIK_CLIENT_SECRET" = config.age.secrets.linkwardenClientSecret.path;
        "NEXTAUTH_SECRET" = config.age.secrets.linkwardenNextAuthSecret.path;
      };
    };

    agindin.services.caddy.proxyHosts = mkIf config.agindin.services.caddy.enable [
      {
        domain = cfg.domain;
        port = globalVars.ports.linkwarden;
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
      dataDir
    ];

    agindin.impermanence.systemDirectories = mkIf config.agindin.impermanence.enable [
      dataDir
    ];
  };
}
