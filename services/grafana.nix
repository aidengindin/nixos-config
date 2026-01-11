{ config, lib, globalVars, ... }:
let
  cfg = config.agindin.services.grafana;
  inherit (lib) mkIf mkOption mkEnableOption types;

  grafanaDir = "/var/lib/grafana";
  prometheusDir = "prometheus2";  # under /var/lib
  prometheusDirFull = "/var/lib/${prometheusDir}";
  lokiDir = "/var/lib/loki";
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

    openLokiPort = mkEnableOption "Whether to open the Loki port for external promtail instances";

    dashboards = mkOption {
      description = "Dashboard files to provision";
      default = [];
      type = types.listOf (types.submodule {
        options = {
          name = mkOption {
            type = types.str;
            description = "Dashboard filename (without .json extension)";
          };
          source = mkOption {
            type = types.path;
            description = "Path to dashboard JSON file";
          };
        };
      });
    };

    alerting = {
      enable = mkEnableOption "Grafana alerting with Discord notifications";

      discordWebhookFile = mkOption {
        type = types.path;
        description = "File containing Discord webhook URL";
        default = ../secrets/grafana-discord-webhook-url.age;
      };

      monitoredHosts = mkOption {
        type = types.listOf types.str;
        description = "List of host job names to monitor and alert on";
        default = [];
      };
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
    } // lib.optionalAttrs cfg.alerting.enable {
      grafanaDiscordWebhook = {
        file = cfg.alerting.discordWebhookFile;
        owner = "grafana";
        group = "grafana";
        mode = "0440";
      };
    };

    agindin.services.restic.paths = mkIf config.agindin.services.restic.enable [
      grafanaDir
      prometheusDirFull
      lokiDir
    ];

    services.grafana = {
      enable = true;
      dataDir = "${grafanaDir}";
      settings = {
        server = {
          domain = cfg.host;
          http_addr = "127.0.0.1";
          http_port = globalVars.ports.grafana;
          root_url = "https://${cfg.host}";
        };
        database = {
          type = "postgres";
          name = "grafana";
          user = "grafana";
          host = "/run/postgresql";  # apparently doesn't support specifying a port, so don't change it!
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
              url = "http://localhost:${toString globalVars.ports.prometheus}";
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
              url = "http://localhost:${toString globalVars.ports.loki}";
              uid = "local-loki";
            }
          ];
        };
        dashboards.settings = mkIf (cfg.dashboards != []) {
          providers = [
            {
              name = "Host Monitoring";
              options.path = "/etc/grafana-dashboards";
            }
          ];
        };
        alerting.contactPoints.settings = mkIf cfg.alerting.enable {
          contactPoints = [
            {
              orgId = 1;
              name = "Discord";
              receivers = [
                {
                  uid = "discord-webhook";
                  type = "discord";
                  settings = {
                    url = "$__file{${config.age.secrets.grafanaDiscordWebhook.path}}";
                    message = "{{ .CommonAnnotations.summary }}";
                    title = "[{{ .Status | toUpper }}] {{ .GroupLabels.alertname }}";
                  };
                  disableResolveMessage = false;
                }
              ];
            }
          ];
        };
        alerting.policies.settings = mkIf cfg.alerting.enable {
          policies = [
            {
              orgId = 1;
              receiver = "Discord";
              group_by = ["alertname" "host"];
              group_wait = "30s";
              group_interval = "5m";
              repeat_interval = "4h";
            }
          ];
        };
        alerting.rules.settings = mkIf cfg.alerting.enable {
          groups = [
            {
              orgId = 1;
              name = "Host Monitoring";
              folder = "Infrastructure";
              interval = "1m";
              rules = (lib.flatten (map (host: [
                {
                  uid = "${host}-high-cpu";
                  title = "${host} - High CPU Usage";
                  condition = "C";
                  data = [
                    {
                      refId = "A";
                      relativeTimeRange = {
                        from = 600;
                        to = 0;
                      };
                      datasourceUid = "local-prometheus";
                      model = {
                        expr = "100 - (avg(irate(node_cpu_seconds_total{mode=\"idle\",job=\"${host}\"}[5m])) * 100)";
                        refId = "A";
                      };
                    }
                    {
                      refId = "B";
                      relativeTimeRange = {
                        from = 0;
                        to = 0;
                      };
                      datasourceUid = "__expr__";
                      model = {
                        conditions = [
                          {
                            evaluator = {
                              params = [];
                              type = "gt";
                            };
                            operator.type = "and";
                            query.params = ["B"];
                            reducer.type = "last";
                            type = "query";
                          }
                        ];
                        datasource = {
                          type = "__expr__";
                          uid = "__expr__";
                        };
                        expression = "A";
                        reducer = "last";
                        refId = "B";
                        type = "reduce";
                      };
                    }
                    {
                      refId = "C";
                      relativeTimeRange = {
                        from = 0;
                        to = 0;
                      };
                      datasourceUid = "__expr__";
                      model = {
                        conditions = [
                          {
                            evaluator = {
                              params = [80];
                              type = "gt";
                            };
                            operator.type = "and";
                            query.params = ["C"];
                            reducer.type = "last";
                            type = "query";
                          }
                        ];
                        datasource = {
                          type = "__expr__";
                          uid = "__expr__";
                        };
                        expression = "B";
                        refId = "C";
                        type = "threshold";
                      };
                    }
                  ];
                  noDataState = "NoData";
                  execErrState = "Error";
                  for = "5m";
                  annotations = {
                    summary = "High CPU usage on ${host}: {{ humanize $values.B.Value }}%";
                  };
                  labels = {
                    host = host;
                  };
                }
                {
                  uid = "${host}-high-memory";
                  title = "${host} - High Memory Usage";
                  condition = "C";
                  data = [
                    {
                      refId = "A";
                      relativeTimeRange = {
                        from = 600;
                        to = 0;
                      };
                      datasourceUid = "local-prometheus";
                      model = {
                        expr = "100 * (1 - (node_memory_MemAvailable_bytes{job=\"${host}\"} / node_memory_MemTotal_bytes{job=\"${host}\"}))";
                        refId = "A";
                      };
                    }
                    {
                      refId = "B";
                      relativeTimeRange = {
                        from = 0;
                        to = 0;
                      };
                      datasourceUid = "__expr__";
                      model = {
                        conditions = [
                          {
                            evaluator = {
                              params = [];
                              type = "gt";
                            };
                            operator.type = "and";
                            query.params = ["B"];
                            reducer.type = "last";
                            type = "query";
                          }
                        ];
                        datasource = {
                          type = "__expr__";
                          uid = "__expr__";
                        };
                        expression = "A";
                        reducer = "last";
                        refId = "B";
                        type = "reduce";
                      };
                    }
                    {
                      refId = "C";
                      relativeTimeRange = {
                        from = 0;
                        to = 0;
                      };
                      datasourceUid = "__expr__";
                      model = {
                        conditions = [
                          {
                            evaluator = {
                              params = [90];
                              type = "gt";
                            };
                            operator.type = "and";
                            query.params = ["C"];
                            reducer.type = "last";
                            type = "query";
                          }
                        ];
                        datasource = {
                          type = "__expr__";
                          uid = "__expr__";
                        };
                        expression = "B";
                        refId = "C";
                        type = "threshold";
                      };
                    }
                  ];
                  noDataState = "NoData";
                  execErrState = "Error";
                  for = "5m";
                  annotations = {
                    summary = "High memory usage on ${host}: {{ humanize $values.B.Value }}%";
                  };
                  labels = {
                    host = host;
                  };
                }
                {
                  uid = "${host}-low-disk-space";
                  title = "${host} - Low Disk Space";
                  condition = "C";
                  data = [
                    {
                      refId = "A";
                      relativeTimeRange = {
                        from = 600;
                        to = 0;
                      };
                      datasourceUid = "local-prometheus";
                      model = {
                        expr = "100 - ((node_filesystem_avail_bytes{job=\"${host}\",mountpoint=\"/\"} * 100) / node_filesystem_size_bytes{job=\"${host}\",mountpoint=\"/\"})";
                        refId = "A";
                      };
                    }
                    {
                      refId = "B";
                      relativeTimeRange = {
                        from = 0;
                        to = 0;
                      };
                      datasourceUid = "__expr__";
                      model = {
                        conditions = [
                          {
                            evaluator = {
                              params = [];
                              type = "gt";
                            };
                            operator.type = "and";
                            query.params = ["B"];
                            reducer.type = "last";
                            type = "query";
                          }
                        ];
                        datasource = {
                          type = "__expr__";
                          uid = "__expr__";
                        };
                        expression = "A";
                        reducer = "last";
                        refId = "B";
                        type = "reduce";
                      };
                    }
                    {
                      refId = "C";
                      relativeTimeRange = {
                        from = 0;
                        to = 0;
                      };
                      datasourceUid = "__expr__";
                      model = {
                        conditions = [
                          {
                            evaluator = {
                              params = [85];
                              type = "gt";
                            };
                            operator.type = "and";
                            query.params = ["C"];
                            reducer.type = "last";
                            type = "query";
                          }
                        ];
                        datasource = {
                          type = "__expr__";
                          uid = "__expr__";
                        };
                        expression = "B";
                        refId = "C";
                        type = "threshold";
                      };
                    }
                  ];
                  noDataState = "NoData";
                  execErrState = "Error";
                  for = "10m";
                  annotations = {
                    summary = "Low disk space on ${host} /: {{ humanize $values.B.Value }}% used";
                  };
                  labels = {
                    host = host;
                  };
                }
                {
                  uid = "${host}-systemd-failed";
                  title = "${host} - Systemd Service Failed";
                  condition = "C";
                  data = [
                    {
                      refId = "A";
                      relativeTimeRange = {
                        from = 600;
                        to = 0;
                      };
                      datasourceUid = "local-prometheus";
                      model = {
                        expr = "node_systemd_unit_state{job=\"${host}\",state=\"failed\"} == 1";
                        refId = "A";
                      };
                    }
                    {
                      refId = "B";
                      relativeTimeRange = {
                        from = 0;
                        to = 0;
                      };
                      datasourceUid = "__expr__";
                      model = {
                        conditions = [
                          {
                            evaluator = {
                              params = [];
                              type = "gt";
                            };
                            operator.type = "and";
                            query.params = ["B"];
                            reducer.type = "last";
                            type = "query";
                          }
                        ];
                        datasource = {
                          type = "__expr__";
                          uid = "__expr__";
                        };
                        expression = "A";
                        reducer = "count";
                        refId = "B";
                        type = "reduce";
                      };
                    }
                    {
                      refId = "C";
                      relativeTimeRange = {
                        from = 0;
                        to = 0;
                      };
                      datasourceUid = "__expr__";
                      model = {
                        conditions = [
                          {
                            evaluator = {
                              params = [0];
                              type = "gt";
                            };
                            operator.type = "and";
                            query.params = ["C"];
                            reducer.type = "last";
                            type = "query";
                          }
                        ];
                        datasource = {
                          type = "__expr__";
                          uid = "__expr__";
                        };
                        expression = "B";
                        refId = "C";
                        type = "threshold";
                      };
                    }
                  ];
                  noDataState = "OK";
                  execErrState = "Error";
                  for = "2m";
                  annotations = {
                    summary = "Systemd service(s) failed on ${host}";
                  };
                  labels = {
                    host = host;
                  };
                }
                {
                  uid = "${host}-host-down";
                  title = "${host} - Host Down";
                  condition = "C";
                  data = [
                    {
                      refId = "A";
                      relativeTimeRange = {
                        from = 600;
                        to = 0;
                      };
                      datasourceUid = "local-prometheus";
                      model = {
                        expr = "up{job=\"${host}\"}";
                        refId = "A";
                      };
                    }
                    {
                      refId = "B";
                      relativeTimeRange = {
                        from = 0;
                        to = 0;
                      };
                      datasourceUid = "__expr__";
                      model = {
                        conditions = [
                          {
                            evaluator = {
                              params = [];
                              type = "gt";
                            };
                            operator.type = "and";
                            query.params = ["B"];
                            reducer.type = "last";
                            type = "query";
                          }
                        ];
                        datasource = {
                          type = "__expr__";
                          uid = "__expr__";
                        };
                        expression = "A";
                        reducer = "last";
                        refId = "B";
                        type = "reduce";
                      };
                    }
                    {
                      refId = "C";
                      relativeTimeRange = {
                        from = 0;
                        to = 0;
                      };
                      datasourceUid = "__expr__";
                      model = {
                        conditions = [
                          {
                            evaluator = {
                              params = [1];
                              type = "lt";
                            };
                            operator.type = "and";
                            query.params = ["C"];
                            reducer.type = "last";
                            type = "query";
                          }
                        ];
                        datasource = {
                          type = "__expr__";
                          uid = "__expr__";
                        };
                        expression = "B";
                        refId = "C";
                        type = "threshold";
                      };
                    }
                  ];
                  noDataState = "Alerting";
                  execErrState = "Alerting";
                  for = "3m";
                  annotations = {
                    summary = "${host} is down or unreachable";
                  };
                  labels = {
                    host = host;
                  };
                }
              ]) cfg.alerting.monitoredHosts));
            }
          ];
        };
      };
    };

    services.prometheus = {
      enable = true;
      port = globalVars.ports.prometheus;
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
        server.http_listen_port = globalVars.ports.loki;
        auth_enabled = false;
        memberlist.bind_addr = [ "127.0.0.1" ];

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

    networking.firewall.allowedTCPPorts = mkIf cfg.openLokiPort [
      globalVars.ports.loki
    ];

    agindin.services.caddy.proxyHosts = mkIf config.agindin.services.caddy.enable [{
      domain = cfg.host;
      port = globalVars.ports.grafana;
    }];

    environment.etc = lib.mkMerge (map (dashboard: {
      "grafana-dashboards/${dashboard.name}.json" = {
        source = dashboard.source;
        group = "grafana";
        user = "grafana";
      };
    }) cfg.dashboards);
  };
}

