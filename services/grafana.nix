{ config, lib, pkgs, ... }:
let
  cfg = config.agindin.services.grafana;
  inherit (lib) mkIf mkOption mkEnableOption types;

  containerLib = import ../lib/container.nix { inherit lib pkgs; };

  grafanaDir = "/var/lib/grafana";
  prometheusDir = "prometheus2";  # under /var/lib
  lokiDir = "/var/lib/loki";

  grafanaPort = 10001;
  prometheusPort = 10002;
  lokiPort = 10004;
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
          root_url = "https://${cfg.host}";
        };
        database = {
          type = "postgres";
          name = "grafana";
          user = "grafana";
          host = "/run/postgresql";  # apparently doesn't support specifying a port, so don't change it!
          # host = "/run/postgresql/.s.PGSQL.${toString config.services.postgresql.settings.port}";
        };
        "auth.basic".enabled = false;
        "auth.generic_oauth" = {
          enabled = true;
          name = "Pocket ID";
          client_id = "$__file{${config.age.secrets.grafanaClientId.path}}";
          client_secret = "$__file{${config.age.secrets.grafanaClientSecret.path}}";
          scopes = "openid profile email";
          auth_url = "https://${cfg.oidcHost}/authorize";
          token_url = "https://${cfg.oidcHost}/api/oidc/token";
          api_url = "https://${cfg.oidcHost}/api/oidc/userinfo";
          use_pkce = true;
          allow_sign_up = true;
          role_attribute_path = "is_grafana_admin && 'Admin' || 'Viewer'";
        };
      };
      provision = {
        datasources.settings = {
          prune = true;
          datasources = [
            {
              name = "Prometheus";
              type = "prometheus";
              access = "proxy";
              url = "http://localhost:${toString prometheusPort}";
              uid = "local-prometheus";
              jsonData = {
                httpMethod = "POST";
                prometheusType = "Prometheus";
                cacheLevel = "High";
                timeInterval = "5s";
                incrementalQueryOverlapWindow = "10m";
              };
            }
            {
              name = "Loki";
              type = "loki";
              access = "proxy";
              url = "http://localhost:${toString lokiPort}";
              uid = "local-loki";
            }
          ];
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

    services.loki = {
      enable = true;
      dataDir = lokiDir;
      configuration = {
        server.http_listen_port = lokiPort;
        auth_enabled = false;

        common = {
          path_prefix = lokiDir;
          replication_factor = 1;
          ring = {
            kvstore.store = "inmemory";
            instance_addr = "127.0.0.1";
          };
          storage = {
            filesystem = {
              chunks_directory = "${lokiDir}/chunks";
              rules_directory = "${lokiDir}/rules";
            };
          };
        };

        schema_config = {
          configs = [{
            from = "2024-01-01"; # Set this to a date in the past
            store = "tsdb";
            object_store = "filesystem";
            schema = "v13";
            index = {
              prefix = "index_";
              period = "24h";
            };
          }];
        };

        compactor = {
          working_directory = "${lokiDir}/compactor";
          retention_enabled = true;
          delete_request_store = "filesystem"; # Required for retention
        };

        limits_config = {
          retention_period = "168h"; # 7 days
          reject_old_samples = true;
          reject_old_samples_max_age = "168h";
        };
      };
    };
  };
}

