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

    # Frigate's API reads /var/cache/frigate/preview_frames but doesn't create
    # it on startup (bug in 0.16.3). The upstream module only declares
    # CacheDirectory=frigate and CacheDirectory=frigate/model_cache, so add
    # the missing subdirectory here so systemd creates it on service start.
    systemd.services.frigate.serviceConfig.CacheDirectory = lib.mkAfter [ "frigate/preview_frames" ];

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

    # The upstream Frigate NixOS module configures services.nginx with a vhost
    # for cfg.hostname. By default NixOS nginx adds "listen 0.0.0.0:80" to
    # every vhost, but Caddy already owns port 80. Override to bind only the
    # internal localhost port that Caddy will proxy to.
    #
    # The upstream module also puts "listen 127.0.0.1:5000;" in extraConfig
    # (see nixpkgs#370349). We override extraConfig with lib.mkForce to remove
    # that line so it doesn't duplicate the listen directive generated below.
    # Keep this in sync with upstream if the VOD settings change.
    services.nginx.virtualHosts.${config.networking.hostName} = {
      listen = [
        {
          addr = "127.0.0.1";
          port = globalVars.ports.frigate;
        }
      ];
      extraConfig = lib.mkForce ''
        # vod settings
        vod_base_url "";
        vod_segments_base_url "";
        vod_mode mapped;
        vod_max_mapping_response_size 1m;
        vod_upstream_location /api;
        vod_align_segments_to_key_frames on;
        vod_manifest_segment_durations_mode accurate;
        vod_ignore_edit_list on;
        vod_segment_duration 10000;
        vod_hls_mpegts_align_frames off;
        vod_hls_mpegts_interleave_frames on;

        # file handle caching / aio
        open_file_cache max=1000 inactive=5m;
        open_file_cache_valid 2m;
        open_file_cache_min_uses 1;
        open_file_cache_errors on;
        aio on;

        # https://github.com/kaltura/nginx-vod-module#vod_open_file_thread_pool
        vod_open_file_thread_pool default;

        # vod caches
        vod_metadata_cache metadata_cache 512m;
        vod_mapping_cache mapping_cache 5m 10m;

        # gzip manifest
        gzip_types application/vnd.apple.mpegurl;
      '';
    };

    agindin.services.caddy.proxyHosts = mkIf config.agindin.services.caddy.enable [
      {
        domain = cfg.domain;
        port = globalVars.ports.frigate;
      }
    ];
  };
}
