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

  yamlFormat = pkgs.formats.yaml { };

  mkCameraInputs =
    cam:
    let
      mkInput = path: roles: {
        path = ''rtsp://${cam.username}:{${cam.rtspPasswordEnvVar}}@${cam.host}:${toString cam.rtspPort}${path}'';
        inherit roles;
      };
    in
    if cam.subRtspPath != null then
      [
        (mkInput cam.rtspPath [ "record" ])
        (mkInput cam.subRtspPath [ "detect" ])
      ]
    else
      [ (mkInput cam.rtspPath cam.roles) ];

  cameraSettings = builtins.listToAttrs (
    map (cam: {
      name = cam.name;
      value =
        {
          ffmpeg.inputs = mkCameraInputs cam;
        }
        // lib.optionalAttrs (cam.detectWidth != null || cam.detectHeight != null) {
          detect = lib.filterAttrs (_: v: v != null) {
            width = cam.detectWidth;
            height = cam.detectHeight;
          };
        };
    }) cfg.cameras
  );

  frigateSettings =
    {
      mqtt.enabled = false;
      record = {
        enabled = true;
        retain.days = cfg.retentionDays;
      };
      cameras = cameraSettings;
    }
    // lib.optionalAttrs (cfg.acceleration == "intel") {
      ffmpeg.hwaccel_args = "preset-vaapi";
      detectors.ov = {
        type = "openvino";
        device = "GPU";
      };
      model = {
        width = 300;
        height = 300;
        input_tensor = "nhwc";
        input_pixel_format = "bgr";
        path = "/openvino-model/ssdlite_mobilenet_v2.xml";
        labelmap_path = "/openvino-model/coco_91cl_bkgr.txt";
      };
    };

  configFile = yamlFormat.generate "frigate-config.yml" frigateSettings;
in
{
  options.agindin.services.frigate = {
    enable = mkEnableOption "frigate NVR";

    image = mkOption {
      type = types.str;
      default = "ghcr.io/blakeblackshear/frigate:0.17.1";
      description = "Container image to use.";
    };

    acceleration = mkOption {
      type = types.enum [
        "none"
        "intel"
      ];
      default = "none";
      description = ''
        Hardware acceleration backend. "intel" enables VAAPI for ffmpeg
        decoding AND OpenVINO on the iGPU for object detection. Requires
        /dev/dri to be present.
      '';
    };

    dataDir = mkOption {
      type = types.str;
      default = "/var/lib/frigate";
      description = "Host directory for Frigate's config and database.";
    };

    mediaLocation = mkOption {
      type = types.str;
      default = "/var/lib/frigate/media";
      description = "Host directory for recordings, clips, and snapshots.";
    };

    retentionDays = mkOption {
      type = types.ints.positive;
      default = 30;
      description = "Number of days to retain recordings.";
    };

    domain = mkOption {
      type = types.str;
      default = "frigate.gindin.xyz";
      description = "Public domain name for the Frigate web UI.";
    };

    shmSize = mkOption {
      type = types.str;
      default = "256m";
      description = ''
        Shared memory size for the container. Frigate uses shm for IPC
        between processes; the docker default of 64m is too small.
      '';
    };

    cacheSize = mkOption {
      type = types.str;
      default = "1g";
      description = "Size of the tmpfs mounted at /tmp/cache inside the container.";
    };

    cameras = mkOption {
      default = [ ];
      description = "Cameras to configure in Frigate.";
      type = types.listOf (
        types.submodule {
          options = {
            name = mkOption {
              type = types.str;
              description = "Unique camera identifier.";
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
                RTSP stream path. For Reolink:
                  main stream: /h264Preview_01_main
                  sub stream:  /h264Preview_01_sub
              '';
            };
            subRtspPath = mkOption {
              type = types.nullOr types.str;
              default = null;
              description = ''
                Optional substream path. When set, main → record, sub →
                detect. The `roles` option is ignored when this is set.
                `detectWidth`/`detectHeight` should match the substream
                resolution to avoid Frigate rescaling frames.
              '';
            };
            detectWidth = mkOption {
              type = types.nullOr types.ints.positive;
              default = null;
              description = "Width of frames passed to the detect pipeline.";
            };
            detectHeight = mkOption {
              type = types.nullOr types.ints.positive;
              default = null;
              description = "Height of frames passed to the detect pipeline.";
            };
            rtspPasswordEnvVar = mkOption {
              type = types.str;
              default = "FRIGATE_RTSP_PASSWORD";
              description = "Env var name holding the RTSP password.";
            };
            environmentFile = mkOption {
              type = types.path;
              description = ''
                File containing the RTSP password env var in KEY=VALUE
                format, typically an agenix secret.
              '';
            };
            roles = mkOption {
              type = types.listOf types.str;
              default = [
                "detect"
                "record"
              ];
              description = "Roles for the input stream when no substream is configured.";
            };
          };
        }
      );
    };
  };

  config = mkIf cfg.enable {
    virtualisation.oci-containers.containers.frigate = {
      image = cfg.image;
      volumes = [
        "${configFile}:/config/config.yml:ro"
        "${cfg.dataDir}:/config"
        "${cfg.mediaLocation}:/media/frigate"
        "/etc/localtime:/etc/localtime:ro"
      ];
      environmentFiles = map (cam: cam.environmentFile) cfg.cameras;
      environment = {
        TZ = config.time.timeZone;
      };
      ports = [
        # Bind to localhost; Caddy reverse-proxies the public domain.
        "127.0.0.1:${toString globalVars.ports.frigate}:5000"
      ];
      extraOptions =
        [
          "--shm-size=${cfg.shmSize}"
          "--tmpfs=/tmp/cache:size=${cfg.cacheSize}"
        ]
        ++ lib.optionals (cfg.acceleration == "intel") [
          "--device=/dev/dri:/dev/dri"
          # render group GID on the host; needed so the container's frigate
          # user can open /dev/dri/renderD128 (mode 0660, owned by render).
          "--group-add=${toString config.users.groups.render.gid}"
        ];
    };

    # render group is needed on the host for /dev/dri access by container.
    users.groups.render = mkIf (cfg.acceleration == "intel") { };

    hardware.graphics = mkIf (cfg.acceleration == "intel") {
      enable = true;
      extraPackages = with pkgs; [
        intel-media-driver
        # OpenCL runtime — required for OpenVINO GPU plugin
        intel-compute-runtime
      ];
    };

    systemd.tmpfiles.rules = [
      "d ${cfg.dataDir} 0755 root root - -"
      "d ${cfg.mediaLocation} 0755 root root - -"
    ];

    agindin.impermanence.systemDirectories = mkIf config.agindin.impermanence.enable (
      [ cfg.dataDir ]
      # Only persist mediaLocation if it's not on a separately-mounted disk
      # (which is the typical reason to override it).
      ++ lib.optional (lib.hasPrefix cfg.dataDir cfg.mediaLocation) cfg.mediaLocation
    );

    agindin.services.caddy.proxyHosts = mkIf config.agindin.services.caddy.enable [
      {
        domain = cfg.domain;
        port = globalVars.ports.frigate;
      }
    ];
  };
}
