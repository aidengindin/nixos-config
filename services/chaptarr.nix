{
  config,
  lib,
  pkgs,
  globalVars,
  ...
}:
let
  cfg = config.agindin.services.chaptarr;
  inherit (lib)
    mkEnableOption
    mkIf
    mkOption
    types
    ;

  dataDir = "/var/lib/chaptarr";
  mediaGid = toString config.users.groups.media.gid;
in
{
  options.agindin.services.chaptarr = {
    enable = mkEnableOption ''
      Chaptarr, the maintained fork of the retired Readarr. Acquires ebooks and
      audiobooks: monitors authors, searches indexers synced from Prowlarr, and
      hands grabs to qBittorrent.
    '';

    domain = mkOption {
      type = types.str;
      default = "chaptarr.gindin.xyz";
    };

    image = mkOption {
      type = types.str;
      default = "chaptarr/chaptarr:0.9.936";
      description = ''
        Pinned deliberately rather than tracking `latest`. Chaptarr is pre-1.0
        and publishes a pre-release every few days, so upgrades should be a
        commit you chose to make, not something that lands on a restart.

        Note the Docker tags carry no `v` prefix even though the git tags do,
        and that `latest` currently lags the newest pre-release by weeks.
      '';
    };

    ebookPath = mkOption {
      type = types.str;
      default = config.agindin.services.bookorbit.libraryPath;
      defaultText = lib.literalExpression "config.agindin.services.bookorbit.libraryPath";
      description = ''
        Root folder Chaptarr organises ebooks into. Defaults to BookOrbit's
        library so BookOrbit scans them in place — the same arrangement Radarr
        and Jellyfin have over `/media/movies`.

        Deliberately NOT BookOrbit's Book Dock: files landing there are moved
        into the library on import, which would pull them out from under
        Chaptarr and leave it thinking its own files had gone missing.
      '';
    };

    audiobookPath = mkOption {
      type = types.str;
      default = "/media/audiobooks";
      description = ''
        Root folder for audiobooks, read in place by Audiobookshelf. Safe to
        share: Audiobookshelf only reads, it does not reorganise.
      '';
    };

    downloadPath = mkOption {
      type = types.str;
      default = "${config.agindin.services.arr.mediaPath}/downloads";
      defaultText = lib.literalExpression "\"\${config.agindin.services.arr.mediaPath}/downloads\"";
      description = ''
        qBittorrent's download root. Mounted into the container at the same
        path it has on the host, so the paths qBittorrent reports over its API
        resolve as-is and no Remote Path Mapping is needed.
      '';
    };

    apiKeyFile = mkOption {
      type = types.nullOr types.path;
      default = null;
      description = ''
        Environment file supplying `CHAPTARR__AUTH__APIKEY=...`, so the key
        Prowlarr authenticates with survives a rebuild. Leave null to let
        Chaptarr generate its own on first run.
      '';
    };
  };

  config = mkIf cfg.enable {
    assertions = [
      {
        assertion = config.users.groups ? media;
        message = "Chaptarr needs a `media` group to share the library with BookOrbit and Audiobookshelf";
      }
      {
        assertion = config.virtualisation.docker.enable;
        message = "Chaptarr is distributed only as a container; enable virtualisation.docker";
      }
    ];

    virtualisation.oci-containers.containers.chaptarr = {
      inherit (cfg) image;

      environment = {
        TZ = "America/New_York";
        # Matching BookOrbit, so files the two write into the shared library
        # end up with the same ownership.
        PUID = "1000";
        PGID = mediaGid;
        # Group-writable output: Chaptarr, BookOrbit and Audiobookshelf all
        # reach the library through `media`.
        UMASK = "002";

        CHAPTARR__SERVER__PORT = toString globalVars.ports.chaptarr;
        # Same reasoning as the other *arr apps: Caddy fronts this on the
        # tailnet, so skip the first-run authentication wizard entirely.
        CHAPTARR__AUTH__METHOD = "External";
        CHAPTARR__AUTH__REQUIRED = "DisabledForLocalAddresses";
        CHAPTARR__LOG__ANALYTICSENABLED = "false";
        CHAPTARR__UPDATE__MECHANISM = "external";
      };

      environmentFiles = lib.optional (cfg.apiKeyFile != null) cfg.apiKeyFile;

      # Bind-mounted at their host paths, not the image's /ebooks and
      # /audiobooks conventions, so every path Chaptarr sees matches what
      # qBittorrent and the library servers see.
      volumes = [
        "${dataDir}:/config"
        "${cfg.ebookPath}:${cfg.ebookPath}"
        "${cfg.audiobookPath}:${cfg.audiobookPath}"
        "${cfg.downloadPath}:${cfg.downloadPath}"
      ];

      # Host networking rather than a bridge. Chaptarr has to reach Prowlarr on
      # loopback and qBittorrent at ${globalVars.ips.qbittorrent.local}, which
      # is only routable from the host side of the namespace veth and only
      # accepts the host's own address. From a bridge both depend on Docker
      # masquerading and on the host firewall accepting traffic off docker0;
      # on the host network they are simply reachable.
      extraOptions = [
        "--network=host"
        "--init"
      ];
    };

    systemd.services.docker-chaptarr = {
      # The data directory is an impermanence bind mount. During a switch those
      # mounts race systemd-tmpfiles-resetup, and when the mount wins, tmpfiles
      # has written ownership to the directory underneath and the mounted one
      # stays root-owned. Ordering after the mount and fixing ownership here —
      # at unit start, every start — is the container equivalent of the
      # StateDirectory= the native services use.
      unitConfig.RequiresMountsFor = [ dataDir ];
      serviceConfig.ExecStartPre = [
        "${pkgs.coreutils}/bin/install -d -o 1000 -g ${mediaGid} -m 0750 ${dataDir}"
      ];
    };

    systemd.tmpfiles.rules = [
      # The image's entrypoint expects the config directory to already match
      # PUID/PGID; Docker would otherwise create it root-owned and Chaptarr
      # would fail to write its database.
      "d ${dataDir} 0750 1000 ${mediaGid} -"
      "d ${cfg.audiobookPath} 2775 1000 ${mediaGid} -"
    ];

    agindin.services.caddy.proxyHosts = mkIf config.agindin.services.caddy.enable [
      {
        domain = cfg.domain;
        port = globalVars.ports.chaptarr;
      }
    ];

    agindin.impermanence.systemDirectories = mkIf config.agindin.impermanence.enable [
      dataDir
    ];

    agindin.services.restic.paths = mkIf config.agindin.services.restic.enable [
      dataDir
    ];
  };
}
