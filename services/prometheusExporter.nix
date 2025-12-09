{ config, lib, pkgs, ... }:
let
  cfg = config.agindin.services.prometheusExporter;
  inherit (lib) mkIf mkOption mkEnableOption types;

  hostName = config.networking.hostName;
in {
  options.agindin.services.prometheusExporter = {
    enable = mkEnableOption "prometheusExporter";
    port = mkOption {
     type = types.port;
     default = 10003;
    };
  };

  config = mkIf cfg.enable {
    services.prometheus.exporters = {
      node = {
        enable = true;
        port = cfg.port;
        enabledCollectors = [ "systemd" ];
      };
    };
  };
}

