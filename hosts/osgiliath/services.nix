{
  config,
  globalVars,
  ...
}:
{
  imports = [ ../../services ];

  age.secrets = {
    restic-password = {
      file = ../../secrets/osgiliath-restic-password.age;
      owner = "restic";
      group = "restic";
      mode = "0400";
    };
    restic-b2-env = {
      file = ../../secrets/osgiliath-restic-b2-env.age;
      owner = "restic";
      group = "restic";
    };
  };

  agindin.services = {
    blocky.enable = true;

    postgres.enable = true;

    restic = {
      enable = true;
      passwordPath = config.age.secrets.restic-password.path;
      localBackup = {
        enable = true;
        repository = "/media/backups";
      };
      b2Backup = {
        enable = true;
        bucket = "osgiliath-restic-backup";
        environmentFile = config.age.secrets.restic-b2-env.path;
      };
    };

    caddy = {
      enable = true;
      cloudflareApiKeyFile = ../../secrets/osgiliath-caddy-cloudflare-api-key.age;
    };

    audiobookshelf.enable = true;

    prometheusExporter = {
      enable = true;
      openPort = false;
    };

    promtail.enable = true;

    grafana = {
      enable = true;
      openLokiPort = true;
      prometheusScrapeTargets = [
        {
          name = "osgiliath";
          host = "127.0.0.1";
          port = globalVars.ports.prometheusNodeExporter;
        }
        {
          name = "lorien";
          host = "lorien";
          port = globalVars.ports.prometheusNodeExporter;
        }
        {
          name = "blocky-osgiliath";
          host = "127.0.0.1";
          port = globalVars.ports.blockyHttp;
          metrics_path = "/prometheus";
        }
        {
          name = "blocky-lorien";
          host = "lorien";
          port = globalVars.ports.blockyHttp;
          metrics_path = "/prometheus";
        }
        {
          name = "pocket-id";
          host = "lorien";
          port = globalVars.ports.pocket-id.prometheus;
        }
        {
          name = "miniflux";
          host = "lorien";
          port = globalVars.ports.miniflux;
        }
        {
          name = "postgres-osgiliath";
          host = "127.0.0.1";
          port = globalVars.ports.postgresExporter;
        }
        {
          name = "postgres-lorien";
          host = "lorien";
          port = globalVars.ports.postgresExporter;
        }
        {
          name = "caddy-osgiliath";
          host = "127.0.0.1";
          port = globalVars.ports.caddyMetrics;
        }
        {
          name = "caddy-lorien";
          host = "lorien";
          port = globalVars.ports.caddyMetrics;
        }
        {
          name = "immich";
          host = "127.0.0.1";
          port = 8081;
        }
        {
          name = "grafana";
          host = "127.0.0.1";
          port = globalVars.ports.grafana;
        }
        {
          name = "loki";
          host = "127.0.0.1";
          port = globalVars.ports.loki;
        }
        {
          name = "promtail-osgiliath";
          host = "127.0.0.1";
          port = globalVars.ports.promtail;
        }
        {
          name = "promtail-lorien";
          host = "lorien";
          port = globalVars.ports.promtail;
        }
      ];
      dashboards = [
        {
          name = "infrastructure-overview";
          source = ../../dashboards/infrastructure-overview.json;
        }
        {
          name = "osgiliath-details";
          source = ../../dashboards/osgiliath-details.json;
        }
        {
          name = "lorien-details";
          source = ../../dashboards/lorien-details.json;
        }
        {
          name = "blocky";
          source = ../../dashboards/blocky.json;
        }
        {
          name = "blocky-overview";
          source = ../../dashboards/blocky-overview.json;
        }
        {
          name = "pocket-id";
          source = ../../dashboards/pocket-id.json;
        }
        {
          name = "miniflux";
          source = ../../dashboards/miniflux.json;
        }
        {
          name = "postgres";
          source = ../../dashboards/postgres.json;
        }
        {
          name = "caddy";
          source = ../../dashboards/caddy.json;
        }
        {
          name = "immich";
          source = ../../dashboards/immich.json;
        }
        {
          name = "observability";
          source = ../../dashboards/observability.json;
        }
      ];
      alerting = {
        enable = true;
        monitoredHosts = [
          "osgiliath"
          "lorien"
        ];
      };
    };

    immich = {
      enable = true;
      mediaLocation = "/media/immich";
    };

    calibre-web.enable = true;

    linkwarden.enable = true;

    octoprint.enable = true;

    netalertx.enable = true;
  };
}
