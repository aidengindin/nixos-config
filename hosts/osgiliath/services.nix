{
  config,
  globalVars,
  ...
}:
{
  imports = [ ../../services ];

  # calibre-web-automated imports books as uid 1000 with a umask that leaves its
  # library subdirectories group-unwritable. This default ACL makes everything
  # created under the library group-writable by `media`, so the calibre-news
  # runner (a member of `media`) can prune old Economist issues.
  systemd.tmpfiles.rules = [
    "A+ ${config.agindin.services.calibre-web.calibreLibrary} - - - - d:group:media:rwx"
  ];

  age.secrets = {
    liftosaur-sync-env = {
      file = ../../secrets/liftosaur-sync-env.age;
      owner = "liftosaur-sync";
      group = "liftosaur-sync";
    };
    headache-sync-env = {
      file = ../../secrets/headache-sync-env.age;
      owner = "headache-sync";
      group = "headache-sync";
    };
    anduin-env = {
      file = ../../secrets/anduin-env.age;
      owner = "anduin";
      group = "anduin";
    };
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
    frigate-reolink-rtsp-password = {
      file = ../../secrets/frigate-reolink-rtsp-password.age;
      mode = "0400";
    };
    mosquitto-zigbee2mqtt-password = {
      file = ../../secrets/mosquitto-zigbee2mqtt-password.age;
    };
    mosquitto-homeassistant-password = {
      file = ../../secrets/mosquitto-homeassistant-password.age;
    };
    zigbee2mqtt-mqtt-env = {
      file = ../../secrets/zigbee2mqtt-mqtt-env.age;
    };
  };

  agindin.services = {
    blocky.enable = true;

    postgres.enable = true;

    anduin-postgres.enable = true;

    anduin = {
      enable = true;
      environmentFile = config.age.secrets.anduin-env.path;
      google-health.enable = true;
      withings.enable = true;
      intervals.enable = true;
      liftosaur.enable = true;
      web = {
        enable = true;
        domain = "anduin.gindin.xyz";
        port = globalVars.ports.anduinWeb;
      };
    };

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

    alloy.enable = true;

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
          port = globalVars.ports.immichApiMetrics;
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
          name = "alloy-osgiliath";
          host = "127.0.0.1";
          port = globalVars.ports.alloy;
        }
        {
          name = "alloy-lorien";
          host = "lorien";
          port = globalVars.ports.alloy;
        }
        {
          name = "anduin-web";
          host = "127.0.0.1";
          port = globalVars.ports.anduinWeb;
          metrics_path = "/-/metrics";
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

    calibre-news = {
      enable = true;
      # Runs as the dedicated `calibre-news` system user (member of `media`).
      recipes.economist = {
        recipe = ../../packages/economist-recipe/economist.recipe;
        schedule = "Fri *-*-* 04:00:00";
        outputDir = config.agindin.services.calibre-web.ingestDir;
        cleanup = {
          enable = true;
          directory = "${config.agindin.services.calibre-web.calibreLibrary}/The Economist";
          keep = 4;
        };
      };
    };

    linkwarden.enable = true;

    netalertx.enable = true;

    liftosaur-sync = {
      enable = true;
      environmentFile = config.age.secrets.liftosaur-sync-env.path;
      syncIntervals = "hourly";
    };

    headache-sync = {
      enable = true;
      environmentFile = config.age.secrets.headache-sync-env.path;
      intervals.athleteId = "i95355";
      airtable = {
        baseId = "app6w70TNVJDxqulT";
        tableId = "tbl7fY07el677Jm1L";
        fieldMap = {
          sleep_score = "Sleep score";
          sleep_duration = "Sleep duration";
          hrv = "HRV";
          resting_hr = "RHR";
          tss = "TSS";
          barometric_pressure = "Barometric pressure (inHg)";
          us_aqi = "AQI";
          pm2_5 = "PM2.5";
          tree_pollen = "Tree pollen (UPI)";
          grass_pollen = "Grass pollen (UPI)";
          weed_pollen = "Weed pollen (UPI)";
        };
      };
      location.default = "Jersey City, NJ";
    };

    mosquitto = {
      enable = true;
      users = {
        zigbee2mqtt = {
          passwordFile = config.age.secrets.mosquitto-zigbee2mqtt-password.path;
          acl = [
            "readwrite zigbee2mqtt/#"
            "readwrite homeassistant/#"
          ];
        };
        homeassistant = {
          passwordFile = config.age.secrets.mosquitto-homeassistant-password.path;
          acl = [
            "readwrite zigbee2mqtt/#"
            "readwrite homeassistant/#"
          ];
        };
      };
    };

    zigbee2mqtt = {
      enable = true;
      serialPort = "/dev/serial/by-id/usb-Nabu_Casa_ZBT-2_E072A1FAACDC-if00";
      baudrate = 460800;
      rtscts = true;
      mqtt.credentialsFile = config.age.secrets.zigbee2mqtt-mqtt-env.path;
    };

    frigate = {
      enable = true;
      acceleration = "intel";
      mediaLocation = "/media/frigate";
      retentionDays = 30;
      cameras = [
        {
          name = "reolink";
          host = "10.0.40.154";
          username = "admin";
          rtspPort = 554;
          rtspPath = "/h264Preview_01_main";
          subRtspPath = "/h264Preview_01_sub";
          detectWidth = 896;
          detectHeight = 512;
          rtspPasswordEnvVar = "FRIGATE_RTSP_PASSWORD";
          environmentFile = config.age.secrets.frigate-reolink-rtsp-password.path;
        }
      ];
    };
  };
}
