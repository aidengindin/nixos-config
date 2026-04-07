{
  config,
  lib,
  pkgs,
  globalVars,
  ...
}:
let
  cfg = config.agindin.services.frigate;
  inherit (lib)
    mkEnableOption
    mkIf
    mkOption
    types
    ;
in
{
  options.agindin.services.frigate = {
    enable = mkEnableOption "frigate NVR";

    acceleration = mkOption {
      type = types.enum [
        "none"
        "intel"
      ];
      default = "none";
      description = "Hardware acceleration backend for video decoding.";
    };

    mediaLocation = mkOption {
      type = types.path;
      default = /var/lib/frigate;
      description = ''
        Path where Frigate stores recordings, clips, and its database.
        Defaults to /var/lib/frigate (SSD). Set to e.g. /media/frigate
        to store on a separate HDD. When set to a non-default path, the
        directory is bind-mounted over /var/lib/frigate so Frigate needs
        no special configuration.
      '';
    };

    retentionDays = mkOption {
      type = types.ints.positive;
      default = 30;
      description = "Number of days to retain recordings.";
    };

    domain = mkOption {
      type = types.str;
      default = "frigate.gindin.xyz";
      description = "Public domain name for the Frigate web UI (used for Caddy proxy).";
    };

    cameras = mkOption {
      default = [ ];
      description = "List of cameras to configure in Frigate.";
      type = types.listOf (
        types.submodule {
          options = {
            name = mkOption {
              type = types.str;
              description = "Unique camera identifier used in Frigate config and MQTT topics.";
            };
            host = mkOption {
              type = types.str;
              description = "IP address or hostname of the camera.";
            };
            username = mkOption {
              type = types.str;
              default = "admin";
              description = "RTSP username.";
            };
            rtspPort = mkOption {
              type = types.port;
              default = 554;
              description = "RTSP port on the camera.";
            };
            rtspPath = mkOption {
              type = types.str;
              description = ''
                RTSP stream path. For Reolink cameras:
                  main stream: /h264Preview_01_main
                  sub stream:  /h264Preview_01_sub
              '';
            };
            rtspPasswordEnvVar = mkOption {
              type = types.str;
              default = "FRIGATE_RTSP_PASSWORD";
              description = ''
                Name of the environment variable that holds the RTSP password.
                This variable must be present in the systemd EnvironmentFile
                provided via the environmentFile option.
              '';
            };
            environmentFile = mkOption {
              type = types.path;
              description = ''
                Path to a file (typically an agenix secret) containing the
                RTSP password env var in KEY=VALUE format, e.g.:
                  FRIGATE_RTSP_PASSWORD=mysecretpassword
              '';
            };
            roles = mkOption {
              type = types.listOf types.str;
              default = [
                "detect"
                "record"
              ];
              description = "Roles assigned to this camera's input stream.";
            };
          };
        }
      );
    };
  };

  config = mkIf cfg.enable {
    # Intel VAAPI hardware acceleration
    hardware.graphics = mkIf (cfg.acceleration == "intel") {
      enable = true;
      extraPackages = [ pkgs.intel-media-driver ];
    };

    services.frigate = {
      enable = true;
      hostname = config.networking.hostName;
      # Disable build-time config check: RTSP passwords come from runtime
      # agenix secrets (EnvironmentFile) and aren't available in the sandbox.
      checkConfig = false;
      settings =
        {
          record = {
            enabled = true;
            retain.days = cfg.retentionDays;
          };

          cameras = builtins.listToAttrs (
            map (cam: {
              name = cam.name;
              value = {
                ffmpeg.inputs = [
                  {
                    path = ''rtsp://${cam.username}:{${cam.rtspPasswordEnvVar}}@${cam.host}:${toString cam.rtspPort}${cam.rtspPath}'';
                    roles = cam.roles;
                  }
                ];
              };
            }) cfg.cameras
          );
        }
        // lib.optionalAttrs (cfg.acceleration == "intel") {
          ffmpeg.hwaccel_args = "preset-vaapi";
        };
    };

    # Grant frigate process access to /dev/dri for hardware acceleration.
    # The upstream module already sets SupplementaryGroups = ["render"]; we
    # extend it to also include "video" so all DRI devices are accessible.
    systemd.services.frigate.serviceConfig.SupplementaryGroups = mkIf (cfg.acceleration == "intel") (
      lib.mkAfter [ "video" ]
    );

    # Inject RTSP password(s) from agenix secrets into the frigate service
    systemd.services.frigate.serviceConfig.EnvironmentFile =
      map (cam: cam.environmentFile) cfg.cameras;

    # When using a custom media location, create the directory and bind-mount
    # it over /var/lib/frigate so all Frigate data lands on the target path.
    systemd.tmpfiles.rules = lib.mkIf (cfg.mediaLocation != /var/lib/frigate) [
      "d ${toString cfg.mediaLocation} 0750 frigate frigate - -"
    ];

    systemd.services.frigate.serviceConfig.BindPaths = lib.mkIf (cfg.mediaLocation != /var/lib/frigate) [
      "${toString cfg.mediaLocation}:/var/lib/frigate"
    ];

    # Persist /var/lib/frigate only when not bind-mounting an external path
    # (when using mediaLocation, the target directory persists on its own).
    agindin.impermanence.systemDirectories = mkIf config.agindin.impermanence.enable (
      lib.optionals (cfg.mediaLocation == /var/lib/frigate) [ "/var/lib/frigate" ]
    );

    agindin.services.caddy.proxyHosts = mkIf config.agindin.services.caddy.enable [
      {
        domain = cfg.domain;
        port = globalVars.ports.frigate;
      }
    ];
  };
}
