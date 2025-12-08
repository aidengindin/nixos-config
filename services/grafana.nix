{ config, lib, pkgs, ... }:
let
  cfg = config.agindin.services.grafana;
  inherit (lib) mkIf mkOption mkEnableOption types;

  containerLib = import ../lib/container.nix { inherit lib pkgs; };

  grafanaDir = "/var/lib/grafana";
  prometheusDir = "prometheus2";  # under /var/lib

  grafanaPort = 10001;
  prometheusPort = 10002;

  hostName = config.networking.hostName;
in {
  options.agindin.services.grafana = {
    enable = mkEnableOption "grafana";
    host = mkOption {
      type = types.str;
      default = "grafana.gindin.xyz";
    };
    prometheusScrapeTargets = mkOption {
      description = "List of Prometheus exporters to scrape";
      default = [];
      type = types.listOf (types.submodule {
        options = {
          name = mkOption { type = types.str; };
          host = mkOption { type = types.str; };
          port = mkOption { type = types.port; };
        };
      });
    };
    oauth2ClientIdFile = mkOption {
      type = types.path;
      description = "File containing client ID configured in OIDC provider";
      default = ../secrets/grafana-client-id.age;
    };
    oauth2ClientSecretFile = mkOption {
      type = types.path;
      description = "File containing client secret configured in OIDC provider";
      default = ../secrets/grafana-client-secret.age;
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
        message = "Grafana requires PostgreSQL to be enabled";
      }
    ];

    agindin.services.postgres.ensureUsers = [ "grafana" ];

    age.secrets = {
      grafanaClientId = {
        file = cfg.oauth2ClientIdFile;
        owner = "grafana";
        group = "grafana";
        mode = "0440";
      };
      grafanaClientSecret = {
        file = cfg.oauth2ClientSecretFile;
        owner = "grafana";
        group = "grafana";
        mode = "0440";
      };
    };

    services.grafana = {
      enable = true;
      dataDir = "${grafanaDir}";
      settings = {
        server = {
          domain = cfg.host;
          http_addr = "127.0.0.1";
          http_port = grafanaPort;
        };
        database = {
          type = "postgres";
          name = "grafana";
          user = "grafana";
          host = "/run/postgresql";  # apparently doesn't support specifying a port, so don't change it!
          # host = "/run/postgresql/.s.PGSQL.${toString config.services.postgresql.settings.port}";
        };
        "auth.generic_oauth" = {
          enabled = true;
          name = "Pocket ID";
          client_id = "$__file{${config.age.secrets.grafanaClientId.path}}";
          client_secret = "$__file{${config.age.secrets.grafanaClientSecret.path}}";
          scopes = "openid profile email";
          auth_url = "https://${cfg.oidcHost}/authorize";
          token_url = "https://${cfg.oidcHost}/token";
          api_url = "https://${cfg.oidcHost}/userinfo";
          use_pkce = true;
          allow_sign_up = true;
          role_attribute_path = "contains(groups[*], 'grafana_admins') && 'Admin' || 'Viewer'";
        };
      };
      provision = {
        datasources.settings = {
          prune = true;
          datasources = [{
            name = "Prometheus ${hostName}";
            type = "prometheus";
            access = "proxy";
            url = "http://localhost:${toString prometheusPort}";
            jsonData = {
              httpMethod = "POST";
              prometheusType = "Prometheus";
              cacheLevel = "High";
              timeInterval = "5s";
              incrementalQueryOverlapWindow = "10m";
            };
          }];
        };
      };
    };

    services.prometheus = {
      enable = true;
      port = prometheusPort;
      stateDir = "${prometheusDir}";
      scrapeConfigs = map (c: {
        job_name = c.name;
        static_configs = [{
          targets = [ "${c.host}:${toString c.port}" ];
        }];
      }) cfg.prometheusScrapeTargets;
    };
  };
}

