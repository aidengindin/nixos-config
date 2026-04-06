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

    agindin.impermanence.systemDirectories = mkIf config.agindin.impermanence.enable [
      "/var/lib/frigate"
    ];

    agindin.services.caddy.proxyHosts = mkIf config.agindin.services.caddy.enable [
      {
        domain = "frigate.gindin.xyz";
        port = globalVars.ports.frigate;
      }
    ];
  };
}
