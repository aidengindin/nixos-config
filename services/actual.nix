{
  config,
  lib,
  globalVars,
  ...
}:
let
  cfg = config.agindin.services.actual;
  inherit (lib)
    mkIf
    mkEnableOption
    mkOption
    types
    ;

  # The env file is read by systemd at unit start, so re-encrypting it changes
  # nothing systemd can see and the old credentials stay live. Mapping the
  # runtime path back to the .age ciphertext in the store gives us something
  # that *does* change when the secret is re-encrypted.
  ageSourceOf =
    runtimePath:
    map (secret: secret.file) (
      lib.filter (secret: secret.path == runtimePath) (lib.attrValues config.age.secrets)
    );
in
{
  # Actual Budget, a local-first envelope budgeting app. Two things have to be
  # done by hand after the first deploy:
  #
  #   1. Create an OIDC client in the Pocket ID UI with callback URL
  #      https://<domain>/openid/callback, and put its credentials into
  #      secrets/actual-oidc-env.age as ACTUAL_OPENID_CLIENT_ID= and
  #      ACTUAL_OPENID_CLIENT_SECRET= lines.
  #
  #   2. Sign in once through Pocket ID. The first OpenID login becomes the
  #      server owner, and that can't be changed from the UI afterwards -- so
  #      make sure it's the right account. With user creation in manual mode,
  #      anyone else has to be added under Server -> User Directory, with a
  #      username matching their Pocket ID one, before they can sign in.
  options.agindin.services.actual = {
    enable = mkEnableOption "actual";

    domain = mkOption {
      type = types.str;
      default = "budget.gindin.xyz";
    };

    oidc = {
      issuer = mkOption {
        type = types.str;
        default = "https://auth.gindin.xyz";
        description = "OIDC issuer URL. Discovery is used, so only this is needed.";
      };
      environmentFile = mkOption {
        type = types.path;
        description = ''
          Age-decrypted env file with ACTUAL_OPENID_CLIENT_ID and
          ACTUAL_OPENID_CLIENT_SECRET. Read by systemd as root, so it can stay
          root-owned.
        '';
      };
    };
  };

  config = mkIf cfg.enable {
    services.actual = {
      enable = true;
      # Upstream runs Actual under DynamicUser, which puts its state in
      # /var/lib/private/actual and gives it a transient UID. Neither plays
      # nicely with impermanence, so pin it to a real user. StateDirectory is
      # still upstream's, so the directory is created after the bind mount.
      user = "actual";
      group = "actual";
      settings = {
        hostname = "127.0.0.1";
        port = globalVars.ports.actual;
      };
    };

    users.users.actual = {
      isSystemUser = true;
      group = "actual";
      home = "/var/lib/actual";
    };
    users.groups.actual = { };

    systemd.services.actual = {
      environment = {
        ACTUAL_LOGIN_METHOD = "openid";
        ACTUAL_OPENID_DISCOVERY_URL = cfg.oidc.issuer;
        ACTUAL_OPENID_SERVER_HOSTNAME = "https://${cfg.domain}";
        ACTUAL_OPENID_AUTH_METHOD = "openid";
        # No password fallback: Pocket ID is the only way in.
        ACTUAL_OPENID_ENFORCE = "true";
        # Only users the owner has added can sign in, rather than anyone with
        # a Pocket ID account.
        ACTUAL_USER_CREATION_MODE = "manual";
      };
      serviceConfig = {
        EnvironmentFile = cfg.oidc.environmentFile;
        # Upstream lists server-files and user-files in ReadWritePaths but only
        # creates the parent via StateDirectory. systemd builds the mount
        # namespace before Actual gets a chance to create them, so a fresh
        # install dies at step NAMESPACE. Restating them here creates them at
        # unit start, after the impermanence bind mount.
        #
        # mkForce because upstream already defines StateDirectory.
        StateDirectory = lib.mkForce "actual actual/server-files actual/user-files";
      };
      restartTriggers = ageSourceOf cfg.oidc.environmentFile;
    };

    # Caddy reaches it over loopback, so nothing to open in the firewall.
    agindin.services.caddy.proxyHosts = mkIf config.agindin.services.caddy.enable [
      {
        domain = cfg.domain;
        port = globalVars.ports.actual;
      }
    ];

    agindin.impermanence.systemDirectories = mkIf config.agindin.impermanence.enable [
      "/var/lib/actual"
    ];

    # Everything, including the budget files themselves, is SQLite under here.
    agindin.services.restic.paths = mkIf config.agindin.services.restic.enable [
      "/var/lib/actual"
    ];
  };
}
