{ config, lib, globalVars, ... }:
let
  cfg = config.agindin.services.prometheusExporter;
  inherit (lib) mkIf mkEnableOption;
in {
  options.agindin.services.prometheusExporter = {
    enable = mkEnableOption "prometheusExporter";
    openPort = mkEnableOption "Whether to open the exporter port";
  };

  config = mkIf cfg.enable {
    services.prometheus.exporters = {
      node = {
        enable = true;
        port = globalVars.ports.prometheusNodeExporter;
        enabledCollectors = [ "systemd" ];
      };
    };

    networking.firewall.allowedTCPPorts = mkIf cfg.openPort [
      globalVars.ports.prometheusNodeExporter
    ];
  };
}

