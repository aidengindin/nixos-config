{
  config,
  lib,
  pkgs,
  globalVars,
  ...
}:
let
  cfg = config.agindin.services.dawarich;
  inherit (lib)
    mkIf
    mkEnableOption
    mkOption
    types
    ;
in
{
  # Dawarich is a self-hosted alternative to Google Location History. Two things
  # have to be done by hand after the first deploy, because neither can exist
  # before the service is running:
  #
  #   1. Create an OIDC client in the Pocket ID UI with callback URL
  #      https://<domain>/users/auth/openid_connect/callback, and put its
  #      credentials into secrets/dawarich-oidc-env.age as OIDC_CLIENT_ID= and
  #      OIDC_CLIENT_SECRET= lines.
  #
  #   2. Claim the admin account. Upstream's `rails db:seed` creates an admin
  #      demo@dawarich.app / safepassword whenever the users table is empty, and
  #      OIDC-registered users are *not* admin. So: log in as demo, log out,
  #      "Sign in with Pocket ID" (which auto-registers you), log back in as
  #      demo, Settings -> Users -> your account -> toggle admin, then delete
  #      the demo user.
  #
  # The API key on your account page is what services/intervals-dawarich-sync.nix
  # and the Home Assistant integration authenticate with. Home Assistant is wired
  # up outside this repo: install AlbinLind/dawarich-home-assistant through HACS,
  # point it at https://<domain> with that key, and pick the phone's
  # device_tracker entity.
  options.agindin.services.dawarich = {
    enable = mkEnableOption "Dawarich location history";

    domain = mkOption {
      type = types.str;
      default = "dawarich.gindin.xyz";
    };

    oidc = {
      issuer = mkOption {
        type = types.str;
        default = "https://auth.gindin.xyz";
        description = "OIDC issuer URL. Discovery is used, so only this is needed.";
      };
      providerName = mkOption {
        type = types.str;
        default = "Pocket ID";
        description = "Label shown on Dawarich's sign-in button.";
      };
      environmentFile = mkOption {
        type = types.path;
        description = "Age-decrypted env file with OIDC_CLIENT_ID and OIDC_CLIENT_SECRET.";
      };
    };
  };

  config = mkIf cfg.enable {
    services.dawarich = {
      enable = true;
      localDomain = cfg.domain;
      webPort = globalVars.ports.dawarich;

      # Caddy fronts this instead. Upstream's nginx vhost exists only to serve
      # ${pkgs.dawarich}/public directly and fall through to Puma, and dawarich
      # sets config.public_file_server.enabled unconditionally in production, so
      # Puma serves its own assets and a plain reverse_proxy is enough. Caddy
      # forwards the /cable websocket transparently.
      configureNginx = false;

      automaticMigrations = true;

      # Managed through agindin.services.postgres below rather than by the
      # upstream module, so that postgres-backup picks the database up along
      # with every other one. Upstream's defaults for host/port/name/user
      # already match this repo's Postgres, so only createLocally changes.
      database.createLocally = false;

      redis.createLocally = true;

      extraEnvFiles = [ cfg.oidc.environmentFile ];

      environment = {
        # Caddy terminates TLS. This also switches on Rails' force_ssl, which is
        # why nothing should reach the service over plain HTTP — see the
        # dawarichUrl note in services/intervals-dawarich-sync.nix.
        APPLICATION_PROTOCOL = "https";

        # Dawarich only offers OIDC in self-hosted mode, and only when both the
        # client ID and secret are present; they arrive via extraEnvFiles.
        OIDC_ISSUER = cfg.oidc.issuer;
        OIDC_REDIRECT_URI = "https://${cfg.domain}/users/auth/openid_connect/callback";
        OIDC_PROVIDER_NAME = cfg.oidc.providerName;
        OIDC_AUTO_REGISTER = "true";
        # Explicit rather than relying on the default: with OIDC in front, an
        # open password-signup form is the one thing that would undo it.
        ALLOW_EMAIL_PASSWORD_REGISTRATION = "false";

        # Belt and braces. config/puma.rb only sets `port`, which leaves Puma
        # bound to 0.0.0.0; `rails server` passes BINDING through as -b. The
        # firewall is the real control here — 8420 is not opened on any
        # interface — but there is no reason to listen wider than Caddy needs.
        BINDING = "127.0.0.1";
      };
    };

    agindin.services.postgres = {
      enable = true;
      ensureUsers = [ "dawarich" ];
      extensions = [ (ps: [ ps.postgis ]) ];
    };

    # What the upstream module does inside its database.createLocally branch.
    # Replicating it is the entire cost of managing the database ourselves.
    # https://github.com/Freika/dawarich/blob/1.7.5/db/schema.rb
    systemd.services.postgresql-setup.serviceConfig.ExecStartPost = [
      (pkgs.writeShellScript "dawarich-postgis-setup" ''
        ${lib.getExe' config.services.postgresql.package "psql"} \
          -d dawarich \
          -c "CREATE EXTENSION IF NOT EXISTS postgis;" \
          -c "SELECT postgis_extensions_upgrade();"
      '')
    ];

    agindin.services.caddy.proxyHosts = mkIf config.agindin.services.caddy.enable [
      {
        domain = cfg.domain;
        port = globalVars.ports.dawarich;
      }
    ];

    agindin.services.restic.paths = mkIf config.agindin.services.restic.enable [
      # Holds uploaded imports and the generated secret_key_base, without which
      # every session cookie in a restored instance would be invalid.
      "/var/lib/dawarich"
    ];

    agindin.impermanence.systemDirectories = mkIf config.agindin.impermanence.enable [
      "/var/lib/dawarich"
      "/var/lib/redis-dawarich"
    ];
  };
}
