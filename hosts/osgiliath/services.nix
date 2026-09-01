{
  config,
  globalVars,
  ...
}:
{
  imports = [ ../../services ];

  # BookOrbit, like calibre-web-automated before it, files books as uid 1000
  # with a umask that leaves its library subdirectories group-unwritable. This
  # default ACL keeps everything created under the library group-writable by
  # `media`, which the other members of that group rely on.
  systemd.tmpfiles.rules = [
    "A+ ${config.agindin.services.bookorbit.libraryPath} - - - - d:group:media:rwx"
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
    economist-cookies = {
      file = ../../secrets/economist-cookies.age;
      owner = "calibre-news";
      group = "calibre-news";
      mode = "0400";
    };
    hermes-env = {
      file = ../../secrets/hermes-env.age;
      owner = "hermes";
      group = "hermes";
      mode = "0440";
    };
    hermes-intervals-env = {
      file = ../../secrets/intervals-env.age;
      owner = "hermes";
      group = "hermes";
      mode = "0440";
    };
    hermes-grafana-token = {
      file = ../../secrets/grafana-mcp-token.age;
      owner = "hermes";
      group = "hermes";
      mode = "0440";
    };
    arr-api-keys = {
      file = ../../secrets/arr-api-keys.age;
      mode = "0400";
    };
    airvpn-wireguard-private-key = {
      file = ../../secrets/airvpn-wireguard-private-key.age;
      mode = "0400";
    };
    airvpn-wireguard-preshared-key = {
      file = ../../secrets/airvpn-wireguard-preshared-key.age;
      mode = "0400";
    };
    hermes-homeassistant-token = {
      file = ../../secrets/homeassistant-token.age;
      owner = "hermes";
      group = "hermes";
      mode = "0440";
    };
  };

  agindin.services = {
    blocky.enable = true;

    hermes = {
      enable = true;
      environmentFile = config.age.secrets.hermes-env.path;
      matrix = {
        enable = true;
      };
      wiki.enable = true;
      webSearch.backend = "tavily";
      # Tuned down from upstream's 10/6: Matrix exchanges here are short
      # enough that neither threshold had ever fired, and the built-in
      # memory stores were still empty after a week of daily use.
      memory = {
        nudgeInterval = 4;
        flushMinTurns = 2;
      };
    };

    # Floating DNS VIP (10.88.88.8) shared with lorien via keepalived/VRRP.
    # osgiliath is the backup holder (lower priority).
    dnsFailover = {
      enable = true;
      virtualIp = "10.88.88.8/24";
      interface = "eno1";
      state = "BACKUP";
      priority = 100;
    };

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

    # qBittorrent runs inside a WireGuard network namespace; everything else in
    # the stack talks to it over a veth pair. The values below come from the
    # WireGuard config generated in the AirVPN client area — see the comments on
    # the options in services/arr.nix for what each one wants.
    arr = {
      enable = true;
      apiKeyFile = config.age.secrets.arr-api-keys.path;
      vpn = {
        # v4 only: the namespace runs with IPv6 disabled, so the v6 address and
        # resolver from the generated config are deliberately dropped.
        address = "10.176.64.146/32";
        dns = "10.128.0.1";
        endpoint = "america3.vpn.airdns.org:1637";
        peerPublicKey = "PyLCXAQT8KkM4T+dUsOQfn+Ub3pGxfGlxkIApuig+hk=";
        mtu = 1320;
        # Must match the port AirVPN assigned in the client area, and that
        # forward's "Local port" has to be set to the same number.
        forwardedPort = 5159;
        privateKeyFile = config.age.secrets.airvpn-wireguard-private-key.path;
        presharedKeyFile = config.age.secrets.airvpn-wireguard-preshared-key.path;
      };
    };

    jellyfin = {
      enable = true;
      # Same iGPU that Frigate uses for detection.
      hardwareAcceleration.enable = true;
    };

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

    # calibre-web-automated is retired; BookOrbit owns books.gindin.xyz. The
    # module and its DRM plugin package are kept in-tree but unused.
    bookorbit = {
      enable = true;
      # auth.gindin.xyz resolves to a tailnet address, which BookOrbit's SSRF
      # guard treats as private (CGNAT) and refuses to fetch discovery from.
      allowLocalOidcIssuers = true;
    };

    # Replaces the DeACSM Calibre plugin that calibre-web-automated ran
    # in-container: fulfills .acsm files with libgourou and drops the
    # DRM-free result into BookOrbit's Book Dock.
    acsm.enable = true;

    calibre-news = {
      enable = true;
      # Runs as the dedicated `calibre-news` system user (member of `media`).
      recipes.economist = {
        recipe = ../../packages/economist-recipe/economist.recipe;
        schedule = "Fri *-*-* 04:00:00";
        cookieFile = config.age.secrets.economist-cookies.path;
        outputDir = config.agindin.services.bookorbit.dockPath;
        # Pruning is off until BookOrbit's library layout is settled. Where a
        # finalized dock file lands depends on the library's organization mode
        # and naming pattern, and the prune step no-ops silently on a directory
        # that does not exist — so a guessed path would look like it works while
        # issues piled up. Re-enable with the real path once one has landed.
        # cleanup = { enable = true; directory = "..."; keep = 4; };
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
