{
  config,
  lib,
  pkgs,
  globalVars,
  ...
}:
let
  cfg = config.agindin.services.jellyfin;
  inherit (lib)
    mkEnableOption
    mkForce
    mkIf
    mkOption
    types
    ;
in
{
  options.agindin.services.jellyfin = {
    enable = mkEnableOption "Whether to enable Jellyfin.";

    host = mkOption {
      type = types.str;
      default = "jellyfin.gindin.xyz";
    };

    hardwareAcceleration = {
      enable = mkEnableOption "Intel VA-API transcoding for Jellyfin";
      device = mkOption {
        type = types.path;
        default = "/dev/dri/renderD128";
      };
    };

    transcodePath = mkOption {
      type = types.nullOr types.path;
      default = null;
      example = "/media/jellyfin-transcodes";
      description = ''
        Directory to hold in-progress transcodes, bind-mounted over the
        transcode subdirectory of Jellyfin's cache.

        Jellyfin keeps every HLS segment of a transcode until the session
        ends, so one stream can write out the whole re-encoded file: a
        4K Dolby Vision remux at 72 Mbit/s is about 140 GB over its runtime.
        Left in the default cache that lands on the root filesystem, next to
        PostgreSQL and the rest of the state, where filling up takes the host
        down. Point this at bulk storage so a long transcode can only ever
        exhaust a disk nothing else depends on.

        Null keeps Jellyfin's default location.
      '';
    };
  };

  config = mkIf cfg.enable {
    assertions = [
      {
        assertion = config.users.groups ? media;
        message = "Jellyfin needs a `media` group to read the shared library";
      }
    ];

    services.jellyfin = {
      enable = true;
      # The unit runs with PrivateUsers=true, which maps only the unit's own
      # user and group into the namespace and turns every other group into
      # `nobody`. A supplementary group would therefore not grant access to the
      # shared library, so `media` has to be Jellyfin's primary group.
      group = "media";

      hardwareAcceleration = mkIf cfg.hardwareAcceleration.enable {
        enable = true;
        # VA-API, not QSV. QSV needs a Media SDK / oneVPL runtime, and this
        # hardware has neither available: vpl-gpu-rt only covers Gen12+, and
        # intel-media-sdk (the one runtime that would drive Gen9.5) is marked
        # insecure in nixpkgs. Without a runtime, `-init_hw_device qsv` fails
        # outright and every transcode dies with "FFmpeg exited with code 171".
        type = "vaapi";
        inherit (cfg.hardwareAcceleration) device;
      };

      # Own encoding.xml from here instead of leaving it to the Dashboard, so
      # the transcoding setup is reproducible. The trade: changes made under
      # Dashboard > Playback > Transcoding are reverted on the next restart.
      forceEncodingConfig = cfg.hardwareAcceleration.enable;

      transcoding = mkIf cfg.hardwareAcceleration.enable {
        enableHardwareEncoding = true;
        enableToneMapping = true;
        enableSubtitleExtraction = true;
        # Everything this generation of Intel QSV decodes in fixed-function
        # hardware. AV1 decode needs Arc or 11th-gen+; harmless if unsupported,
        # ffmpeg just falls back to software for that codec.
        hardwareDecodingCodecs = {
          h264 = true;
          hevc = true;
          mpeg2 = true;
          vc1 = true;
          vp8 = true;
          vp9 = true;
          hevc10bit = true;
        };
        hardwareEncodingCodecs.hevc = true;
        # Defaults to false, and forceEncodingConfig writes that default into
        # encoding.xml on every restart. Unthrottled, ffmpeg encodes as fast as
        # the iGPU allows rather than tracking playback, so the HLS segments for
        # an entire file pile up in the transcode cache long before anyone
        # watches them. On 2026-10-02 a 51 Mbps 2160p transcode of a UHD remux
        # did that for an hour and filled osgiliath's root filesystem, taking
        # PostgreSQL, Mosquitto and everything behind them down.
        throttleTranscoding = true;
      };
    };

    # Upstream creates these with systemd.tmpfiles, which during a switch races
    # the impermanence bind mount for the data directory and can leave it owned
    # by root — the pre-start script then fails copying encoding.xml into a
    # config directory that does not exist. StateDirectory runs at unit start,
    # after mounts, and recursively fixes ownership if it is already wrong.
    systemd.services.jellyfin.serviceConfig = lib.mkMerge [
      {
        StateDirectory = "jellyfin jellyfin/config jellyfin/log";
        StateDirectoryMode = "0700";
        CacheDirectory = "jellyfin";
        CacheDirectoryMode = "0700";
      }
      # Opening the render node needs the `render` group, and PrivateUsers can
      # only map one group. Trade the user namespace for GPU access.
      (mkIf cfg.hardwareAcceleration.enable {
        PrivateUsers = mkForce false;
        SupplementaryGroups = [ "render" ];
      })
      # A bind mount rather than cacheDir, so only the transcodes move. The
      # rest of the cache is small random IO that belongs on the SSD, while
      # transcode segments are large sequential writes a spinning disk serves
      # fine. Jellyfin offers no option for the transcode path alone, and
      # forceEncodingConfig owns encoding.xml, so the path is redirected
      # underneath it instead. Set up at unit start, after CacheDirectory has
      # created the parent.
      (mkIf (cfg.transcodePath != null) {
        BindPaths = [ "${cfg.transcodePath}:${config.services.jellyfin.cacheDir}/transcodes" ];
      })
    ];

    # Without this Jellyfin can start before the bulk disk is mounted and
    # bind a path that is still an empty mountpoint on the root filesystem,
    # which is the failure this redirect exists to prevent.
    systemd.services.jellyfin.unitConfig = mkIf (cfg.transcodePath != null) {
      RequiresMountsFor = cfg.transcodePath;
    };

    systemd.tmpfiles.rules = mkIf (cfg.transcodePath != null) [
      "d ${cfg.transcodePath} 0700 jellyfin ${config.services.jellyfin.group} -"
    ];

    users.groups.render = mkIf cfg.hardwareAcceleration.enable { };

    hardware.graphics = mkIf cfg.hardwareAcceleration.enable {
      enable = true;
      extraPackages = [
        pkgs.intel-media-driver
        # OpenCL, needed by tonemap_opencl for HDR content. The non-legacy
        # intel-compute-runtime supports 12th Gen and newer only; on this
        # Gen9.5 iGPU it loads but reports zero OpenCL platforms.
        pkgs.intel-compute-runtime-legacy1
      ];
    };

    agindin.services.caddy.proxyHosts = mkIf config.agindin.services.caddy.enable [
      {
        domain = cfg.host;
        port = globalVars.ports.jellyfin;
      }
    ];

    agindin.impermanence.systemDirectories = mkIf config.agindin.impermanence.enable [
      config.services.jellyfin.dataDir
    ];

    agindin.services.restic.paths = mkIf config.agindin.services.restic.enable [
      config.services.jellyfin.dataDir
    ];
  };
}
