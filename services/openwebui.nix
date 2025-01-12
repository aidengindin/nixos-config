{ config, lib, pkgs, ... }:
let
  cfg = config.agindin.services.openwebui;
  inherit (lib) mkIf mkEnableOption mkOption types;
in
{
  options.agindin.services.openwebui = {
    enable = mkEnableOption "openwebui";
    tag = mkOption {
      type = types.str;
      example = "git-4269df0";
      description = "Tag of the openwebui image to use";
    };
    subnet = mkOption {
      type = types.str;
      default = "172.101.0.0/24";
      description = "Subnet for the openwebui Docker network to use";
    };
    ip = mkOption {
      type = types.str;
      default = "172.101.0.10";
      description = "IP address for the openwebui container";
    };
    host = mkOption {
      type = types.str;
      default = "openwebui.gindin.xyz";
      description = "Host for the openwebui container";
    };
  };

  config = mkIf cfg.enable {
    age.secrets = {
      openwebui-env.file = ../secrets/openwebui-env.age;
    };

    systemd = {
      tmpfiles.rules = [
        "d /var/lib/openwebui 0750 root root -"
      ];
      services = {
        create-openwebui-network = {
          description = "Create Docker network for openwebui containers";
          serviceConfig.type = "oneshot";
          wantedBy = [ "multi-user.target" ];
          after = [ "docker.service" ];
          script = ''
            if ! ${pkgs.docker}/bin/docker network inspect openwebui-network &>/dev/null; then
              echo "openwebui-network does not exist. Creating..."
              if ${pkgs.docker}/bin/docker network create --subnet=${cfg.subnet} openwebui-network; then
                echo "Network created with subnet ${cfg.subnet}"
              else
                echo "Failed to create network."
                exit 1
              fi
            fi
          '';
        };

        docker-openwebui.after = [ "create-openwebui-network.service" ];
      };
    };

    virtualisation.oci-containers.containers = {
      openwebui = {
        image = "openwebui/openwebui:${cfg.tag}";
        volumes = [
          "/var/lib/openwebui:/app/backend/data"
        ];
        extraOptions = [
          "--restart=unless-stopped"
          "--rm=false"
          "--network=openwebui-network"
          "--ip=${cfg.ip}"
          "--env-file ${config.age.secrets.openwebui-env.path}"
        ];
      };
    };
  };
}
