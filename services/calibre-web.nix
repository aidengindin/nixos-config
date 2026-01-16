{ config, lib, pkgs, globalVars, ... }:
let
  cfg = config.agindin.services.calibre-web;
  inherit (lib) mkIf mkEnableOption mkOption types;

  # DeDRM plugin from noDRM fork
  dedrmPlugin = pkgs.fetchurl {
    url = "https://github.com/noDRM/DeDRM_tools/releases/download/v10.0.3/DeDRM_tools_10.0.3.zip";
    sha256 = "8649e30efb0c26e9cca1131df4c9d02d51eccb5028d396cce857f0fa75a62849";
  };

  # DeACSM plugin - fetch pre-built from releases
  deacsmPlugin = pkgs.fetchurl {
    url = "https://github.com/Leseratte10/acsm-calibre-plugin/releases/download/v0.0.16/DeACSM_0.0.16.zip";
    sha256 = "0l0bhx8kdvmvfn9z0fpkl488kgf1rcv3vchzgjjwwnwzgfi1pxmm";
  };

  # Combined plugins package
  calibrePlugins = pkgs.stdenv.mkDerivation {
    pname = "calibre-drm-plugins";
    version = "1.0";

    nativeBuildInputs = [ pkgs.unzip ];

    buildCommand = ''
      mkdir -p $out
      # Extract DeDRM from the tools archive
      ${pkgs.unzip}/bin/unzip ${dedrmPlugin}
      # The zip extracts directly to current directory
      cp DeDRM_plugin.zip $out/
      # Copy DeACSM plugin (already a zip)
      cp ${deacsmPlugin} $out/DeACSM.zip
    '';
  };
in
{
  options.agindin.services.calibre-web = {
    enable = mkEnableOption "calibre-web";

    domain = mkOption {
      type = types.str;
      default = "books.gindin.xyz";
      description = "Domain name for the calibre-web instance";
    };

    calibreLibrary = mkOption {
      type = types.str;
      default = "/media/books";
      description = "Path to the Calibre library (containing metadata.db)";
    };

    dataDir = mkOption {
      type = types.str;
      default = "/var/lib/calibre-web";
      description = "Directory for calibre-web configuration and database";
    };

    ingestDir = mkOption {
      type = types.str;
      default = "/var/lib/calibre-web/ingest";
      description = "Directory for automatic book ingestion";
    };

    enableDrmPlugins = mkOption {
      type = types.bool;
      default = true;
      description = "Enable DeDRM and DeACSM plugins for removing DRM from ebooks";
    };
  };

  config = mkIf cfg.enable {
    virtualisation.oci-containers.containers = {
      calibre-web = {
        image = "ghcr.io/crocodilestick/calibre-web-automated:latest";
        volumes = [
          "${cfg.dataDir}:/config"
          "${cfg.calibreLibrary}:/calibre-library"
          "${cfg.ingestDir}:/cwa-book-ingest"
        ];
        environment = {
          PUID = "1000";
          PGID = "991";  # media group
          TZ = "America/New_York";
          OAUTHLIB_RELAX_TOKEN_SCOPE = "1";
          CALIBRE_CONFIG_DIRECTORY = "/config/.config/calibre";
        };
        ports = [ "${toString globalVars.ports.calibre-web}:8083" ];
        extraOptions = [
          "--rm=false"
          "--restart=always"
        ];
      };
    };

    # Create directories with appropriate permissions
    systemd.tmpfiles.rules = [
      "d '${cfg.dataDir}' 0755 1000 1000 -"
      "d '${cfg.calibreLibrary}' 0775 1000 ${if config.users.groups ? media then "media" else "1000"} -"
      "d '${cfg.ingestDir}' 0775 1000 ${if config.users.groups ? media then "media" else "1000"} -"
    ] ++ (lib.optionals cfg.enableDrmPlugins [
      "d '${cfg.dataDir}/.config' 0755 1000 1000 -"
      "d '${cfg.dataDir}/.config/calibre' 0755 1000 1000 -"
      "d '${cfg.dataDir}/.config/calibre/plugins' 0755 1000 1000 -"
    ]);

    # Provision DRM removal plugins
    systemd.services.calibre-web-plugins = mkIf cfg.enableDrmPlugins {
      description = "Install Calibre DRM removal plugins";
      wantedBy = [ "multi-user.target" ];
      after = [ "docker-calibre-web.service" ];
      requires = [ "docker.service" "docker-calibre-web.service" ];
      path = [ config.virtualisation.docker.package ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      script = ''
        PLUGINS_DIR="${cfg.dataDir}/.config/calibre/plugins"

        # Ensure plugins directory exists and copy plugin files
        mkdir -p "$PLUGINS_DIR"

        # Wait for container to exist and be running
        echo "Waiting for calibre-web container..."
        for i in {1..30}; do
          if docker ps | grep -q calibre-web; then
            echo "Container found"
            break
          fi
          sleep 2
        done

        echo "Copying DeDRM plugin from ${calibrePlugins}/DeDRM_plugin.zip"
        cp -fv ${calibrePlugins}/DeDRM_plugin.zip "$PLUGINS_DIR/"
        chown 1000:991 "$PLUGINS_DIR/DeDRM_plugin.zip"

        echo "Copying DeACSM plugin from ${calibrePlugins}/DeACSM.zip"
        cp -fv ${calibrePlugins}/DeACSM.zip "$PLUGINS_DIR/"
        chown 1000:991 "$PLUGINS_DIR/DeACSM.zip"

        echo "Verifying files exist after copy:"
        ls -la "$PLUGINS_DIR/"/*.zip

        # Wait for Calibre to be ready inside the container
        echo "Waiting for calibre-web container to be ready..."
        for i in {1..30}; do
          if docker exec calibre-web calibre-customize --version &>/dev/null; then
            echo "Container is ready"
            break
          fi
          sleep 2
        done

        # Verify container can see the files
        echo "Checking if container can see plugin files:"
        docker exec calibre-web ls -la /config/.config/calibre/plugins/*.zip || true

        echo "Verifying files still exist on host before installation:"
        ls -la "$PLUGINS_DIR/"/*.zip

        # Install plugins inside the container - copy to /tmp first to avoid bind mount issues
        # Install DeACSM first, then DeDRM to ensure both get registered properly
        echo "Installing DeACSM plugin..."
        docker exec calibre-web sh -c "cp /config/.config/calibre/plugins/DeACSM.zip /tmp/ && calibre-customize -a /tmp/DeACSM.zip" || true

        echo "Installing DeDRM plugin..."
        docker exec calibre-web sh -c "cp /config/.config/calibre/plugins/DeDRM_plugin.zip /tmp/ && calibre-customize -a /tmp/DeDRM_plugin.zip" || true

        # Verify both plugins are installed
        echo "Verifying plugins are installed:"
        docker exec calibre-web calibre-customize -l | grep -E "DeDRM|DeACSM" || echo "Warning: plugins may not be visible yet"

        echo "Plugins installed successfully"
      '';
    };

    agindin.impermanence.systemDirectories = mkIf config.agindin.impermanence.enable [
      cfg.dataDir
      cfg.ingestDir
    ];

    agindin.services.caddy.proxyHosts = mkIf config.agindin.services.caddy.enable [{
      domain = cfg.domain;
      port = globalVars.ports.calibre-web;
    }];
  };
}
