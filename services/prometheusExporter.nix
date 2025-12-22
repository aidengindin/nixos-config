{ config, lib, globalVars, ... }:
let
  cfg = config.agindin.services.prometheusExporter;
  inherit (lib) mkIf mkOption mkEnableOption types;
in {
  options.agindin.services.prometheusExporter = {
    enable = mkEnableOption "prometheusExporter";
    port = mkOption {
     type = types.port;
     default = globalVars.ports.prometheusNodeExporter;
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

