{ config, lib, pkgs, ... }:
let
  cfg = config.agindin.services.dnsmasq;
  inherit (lib) mkIf mkEnableOption mkOption mkForce types;
in
{
  options.agindin.services.dnsmasq = {
    enable = mkEnableOption "dnsmasq";
    port = mkOption {
      type = types.int;
      example = 53;
      description = "Port to listen on";
    };
    upstreamServer = mkOption {
      type = types.str;
      example = "1.1.1.1";
      description = "IP of the upstream DNS server to use";
    };
  };

  config = mkIf cfg.enable {
    containers.dnsmasq = {
      ephemeral = true;
      autoStart = true;
      config = { config, pkgs }: {
        services.dnsmasq = {
          enable = true;
          port = cfg.port;
        };
        networking.firewall = {
          allowedTCPPorts = mkForce [];
          allowedUDPPorts = mkForce [ cfg.port ];
        };
      };
    };
  };
}
