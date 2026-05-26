{
  config,
  lib,
  globalVars,
  ...
}:
let
  cfg = config.agindin.services.zigbee2mqtt;
  inherit (lib)
    mkEnableOption
    mkIf
    mkOption
    types
    ;
in
{
  options.agindin.services.zigbee2mqtt = {
    enable = mkEnableOption "zigbee2mqtt";

    serialPort = mkOption {
      type = types.str;
      example = "/dev/serial/by-id/usb-Nabu_Casa_Home_Assistant_Connect_ZBT-2_xxxxxxxx-if00";
      description = ''
        Path to the Zigbee coordinator's serial device. Should be a
        stable `/dev/serial/by-id/...` symlink so it survives reboots
        and USB re-enumeration.
      '';
    };

    serialAdapter = mkOption {
      type = types.enum [
        "auto"
        "ember"
        "zstack"
        "deconz"
        "zigate"
      ];
      default = "ember";
      description = ''
        Coordinator firmware family. The Home Assistant SkyConnect /
        ZBT-2 ships with Silicon Labs EmberZNet ("ember").
      '';
    };

    baudrate = mkOption {
      type = types.nullOr types.int;
      default = null;
      example = 460800;
      description = ''
        Serial baudrate. Leave null to use the adapter's default. The
        Nabu Casa ZBT-2 requires 460800.
      '';
    };

    rtscts = mkOption {
      type = types.bool;
      default = false;
      description = ''
        Enable hardware (RTS/CTS) flow control. Required for the Nabu
        Casa ZBT-2.
      '';
    };

    mqtt = {
      server = mkOption {
        type = types.str;
        default = "mqtt://127.0.0.1:${toString globalVars.ports.mosquitto}";
        description = "MQTT broker URL (e.g. mqtt://host:1883).";
      };

      baseTopic = mkOption {
        type = types.str;
        default = "zigbee2mqtt";
        description = "Base topic for all zigbee2mqtt messages.";
      };

      credentialsFile = mkOption {
        type = types.path;
        description = ''
          Path to a systemd EnvironmentFile (typically an agenix
          secret) containing MQTT credentials as zigbee2mqtt env-var
          overrides:

              ZIGBEE2MQTT_CONFIG_MQTT_USER=zigbee2mqtt
              ZIGBEE2MQTT_CONFIG_MQTT_PASSWORD=hunter2

          This keeps credentials out of the world-readable
          configuration.yaml.
        '';
      };
    };

    frontend = {
      enable = mkOption {
        type = types.bool;
        default = true;
        description = "Enable the zigbee2mqtt web frontend.";
      };

      port = mkOption {
        type = types.port;
        default = globalVars.ports.zigbee2mqtt;
        description = "Port the frontend listens on (localhost-only).";
      };

      domain = mkOption {
        type = types.str;
        default = "zigbee2mqtt.gindin.xyz";
        description = "Public domain name for Caddy to proxy to the frontend.";
      };
    };
  };

  config = mkIf cfg.enable {
    services.zigbee2mqtt = {
      enable = true;
      settings = {
        homeassistant.enabled = true;
        permit_join = false;
        serial = {
          port = cfg.serialPort;
          adapter = cfg.serialAdapter;
          rtscts = cfg.rtscts;
        } // lib.optionalAttrs (cfg.baudrate != null) { baudrate = cfg.baudrate; };
        mqtt = {
          server = cfg.mqtt.server;
          base_topic = cfg.mqtt.baseTopic;
        };
        frontend = mkIf cfg.frontend.enable {
          enabled = true;
          host = "127.0.0.1";
          port = cfg.frontend.port;
        };
        advanced.log_output = [ "console" ];
      };
    };

    systemd.services.zigbee2mqtt.serviceConfig = {
      EnvironmentFile = cfg.mqtt.credentialsFile;
    };

    agindin.impermanence.systemDirectories = mkIf config.agindin.impermanence.enable [
      "/var/lib/zigbee2mqtt"
    ];

    agindin.services.caddy.proxyHosts =
      mkIf (cfg.frontend.enable && config.agindin.services.caddy.enable)
        [
          {
            domain = cfg.frontend.domain;
            port = cfg.frontend.port;
          }
        ];
  };
}
