{ config, lib, pkgs, ... }:
let
  cfg = config.agindin.services.miniflux;
  inherit (lib) mkIf mkEnableOption mkOption types;

  containerLib = import ../lib/container.nix { inherit lib pkgs; };
in {
  options.agindin.services.miniflux = {
    enable = mkEnableOption "miniflux";
    host = mkOption {
      type = types.str;
      default = "rss.gindin.xyz";
    };
    interface = mkOption {
      type = types.str;
      default = "enp1s0";
      description = "Host network interface to use for NAT";
    };
    oauth2ClientIdFile = mkOption {
      type = types.path;
      description = "File containing client ID configured in OIDC provider";
    };
    oauth2ClientSecretFile = mkOption {
      type = types.path;
      description = "File containing client secret configured in OIDC provider";
    };
    oidcHost = mkOption {
      type = types.str;
      default = "auth.gindin.xyz";
      description = "Host of OIDC provider";
    };
    stateVersion = mkOption {
      type = types.str;
      default = "25.05";
    };
  };

  config = mkIf cfg.enable (containerLib.makeContainer {
    name = "miniflux";
    subnet = "192.168.102.0/24";
    hostAddress = "192.168.102.10";
    localAddress = "192.168.102.11";
    stateVersion = cfg.stateVersion;

    bindMounts = {
      "/secrets/client_id" = {
        hostPath = "${cfg.oauth2ClientIdFile}";
        isReadOnly = true;
      };
      "/secrets/client_secret" = {
        hostPath = "${cfg.oauth2ClientSecretFile}";
        isReadOnly = true;
      };
    };

    openPorts = [ 8080 ];

    extraConfig = {
      services.miniflux = {
        enable = true;
        config = {
          PORT = 8080;
          CREATE_ADMIN = 0;
          OAUTH2_PROVIDER = "oidc";
          OAUTH2_CLIENT_ID_FILE = "/secrets/client_id";
          OAUTH2_CLIENT_SECRET = "/secrets/client_secret";
          OAUTH2_REDIRECT_URL = "https://${cfg.host}/oauth2/oidc/callback";
          OAUTH2_OIDC_DISCOVERY_ENDPOINT = "https://${cfg.oidcHost}";
          OAUTH2_OIDC_PROVIDER_NAME = "PocketID";
          OAUTH2_USER_CREATION = 1;
          DISABLE_LOCAL_AUTH = 1;
        };
      };
    };
  });
}

