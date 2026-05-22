{
  config,
  lib,
  globalVars,
  ...
}:
let
  cfg = config.agindin.services.mosquitto;
  inherit (lib)
    mkEnableOption
    mkIf
    mkOption
    types
    ;
in
{
  options.agindin.services.mosquitto = {
    enable = mkEnableOption "mosquitto MQTT broker";

    port = mkOption {
      type = types.port;
      default = globalVars.ports.mosquitto;
      description = "TCP port the broker listens on.";
    };

    openFirewall = mkOption {
      type = types.bool;
      default = true;
      description = "Open the listener port in the firewall.";
    };

    users = mkOption {
      default = { };
      description = ''
        MQTT users. Each user must reference a `passwordFile`
        containing the plain-text password (typically an agenix
        secret); mosquitto reads it via systemd credentials, so
        no special file permissions are required. `acl` lines
        follow the mosquitto ACL file format, e.g.
        `"readwrite zigbee2mqtt/#"`.
      '';
      type = types.attrsOf (
        types.submodule {
          options = {
            passwordFile = mkOption {
              type = types.path;
              description = "Path to a file containing the user's plain-text password.";
            };
            acl = mkOption {
              type = types.listOf types.str;
              default = [ ];
              description = "ACL entries granting this user access to topics.";
            };
          };
        }
      );
    };
  };

  config = mkIf cfg.enable {
    services.mosquitto = {
      enable = true;
      persistence = true;
      listeners = [
        {
          port = cfg.port;
          users = lib.mapAttrs (_: u: {
            inherit (u) passwordFile acl;
          }) cfg.users;
        }
      ];
    };

    networking.firewall.allowedTCPPorts = mkIf cfg.openFirewall [ cfg.port ];

    agindin.impermanence.systemDirectories = mkIf config.agindin.impermanence.enable [
      "/var/lib/mosquitto"
    ];
  };
}
