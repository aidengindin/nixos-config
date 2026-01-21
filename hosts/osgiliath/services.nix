{
  config,
  lib,
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
    };

    caddy = {
      enable = true;
      cloudflareApiKeyFile = ../../secrets/osgiliath-caddy-cloudflare-api-key.age;
    };

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

  };
}
