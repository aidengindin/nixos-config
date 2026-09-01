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
      enable = mkEnableOption "Intel QuickSync transcoding for Jellyfin";
      device = mkOption {
        type = types.path;
        default = "/dev/dri/renderD128";
      };
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
        type = "qsv";
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
    ];

    users.groups.render = mkIf cfg.hardwareAcceleration.enable { };

    hardware.graphics = mkIf cfg.hardwareAcceleration.enable {
      enable = true;
      extraPackages = [ pkgs.intel-media-driver ];
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
