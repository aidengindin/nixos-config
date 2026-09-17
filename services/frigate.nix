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
      # 0.17 flipped the default for detect.enabled from true to false, which
      # silently turns off object detection on upgrade.
      detect.enabled = cfg.detect.enable;
      record = {
        enabled = true;
        # 0.17 splits retention into continuous / motion / tracked-object
        # tiers. Continuous is by far the most expensive: a single main-stream
        # camera writes ~30 GB/day, so retaining it for a month costs ~1 TB.
        # Keep a short continuous window, then fall back to motion-only, then
        # to segments overlapping alerts/detections.
        continuous.days = cfg.retention.continuousDays;
        motion.days = cfg.retention.motionDays;
        alerts.retain = {
          days = cfg.retention.alertsDays;
          mode = cfg.retention.alertsMode;
        };
        detections.retain = {
          days = cfg.retention.detectionsDays;
          mode = cfg.retention.detectionsMode;
        };
      };
      cameras = cameraSettings;
    }
    // lib.optionalAttrs (cfg.acceleration == "intel") {
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
    }
    // lib.optionalAttrs (cfg.acceleration == "intel" && cfg.ffmpegHwaccel) {
      ffmpeg.hwaccel_args = "preset-vaapi";
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

    ffmpegHwaccel = mkOption {
      type = types.bool;
      default = false;
      description = ''
        Use VAAPI for ffmpeg decoding. Requires acceleration = "intel".

        This only affects the detect stream: Frigate appends hwaccel args
        solely to the input holding the "detect" role, because the record
        input is a stream copy with nothing to decode. So the only thing this
        buys is offloading substream decode, and it costs a hwdownload of
        every frame back to system memory to reach the detector.

        Off by default because that hwdownload intermittently fails on the
        iGPU ("Failed to sync surface" / "Failed to download frame: -5"),
        killing the ffmpeg process and stalling detection. A detect substream
        is small enough that software decode is cheap.
      '';
    };

    detect = mkOption {
      default = { };
      description = "Object detection settings.";
      type = types.submodule {
        options = {
          enable = mkOption {
            type = types.bool;
            default = true;
            description = ''
              Run object detection. Frigate 0.17 changed the upstream default
              for `detect.enabled` from true to false, so this is set
              explicitly rather than left implicit. With detection off,
              nothing populates the alerts/detections retention tiers and
              recordings are kept on the continuous/motion tiers alone.
            '';
          };
        };
      };
    };

    retention = mkOption {
      default = { };
      description = ''
        Recording retention policy. Frigate keeps a segment for as long as
        the longest matching tier says to, so these stack: continuous is the
        floor for every segment, motion extends segments containing motion,
        and alerts/detections extend segments overlapping tracked objects.

        Continuous retention dominates storage — budget roughly
        (main stream bitrate) x 86400 per camera per day.
      '';
      type = types.submodule {
        options = {
          continuousDays = mkOption {
            type = types.numbers.nonnegative;
            default = 3;
            description = ''
              Days to keep 24/7 footage. Set to 0 to only keep footage that
              matches one of the tiers below.
            '';
          };
          motionDays = mkOption {
            type = types.numbers.nonnegative;
            default = 7;
            description = ''
              Days to keep segments containing motion. This only saves space
              if motion detection is actually selective; an unmasked, noisy
              scene can flag motion on nearly every frame, in which case this
              behaves like continuous retention.
            '';
          };
          alertsDays = mkOption {
            type = types.numbers.nonnegative;
            default = 30;
            description = "Days to keep segments overlapping review alerts.";
          };
          alertsMode = mkOption {
            type = types.enum [
              "all"
              "motion"
              "active_objects"
            ];
            default = "motion";
            description = ''
              Which segments within an alert's time range to keep: "all"
              footage, only segments with "motion", or only segments with
              "active_objects".
            '';
          };
          detectionsDays = mkOption {
            type = types.numbers.nonnegative;
            default = 14;
            description = "Days to keep segments overlapping review detections.";
          };
          detectionsMode = mkOption {
            type = types.enum [
              "all"
              "motion"
              "active_objects"
            ];
            default = "motion";
            description = "Same as alertsMode, for detections.";
          };
        };
      };
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
