{
  config,
  lib,
  globalVars,
  ...
}:
let
  cfg = config.agindin.services.alloy;
  inherit (lib)
    mkIf
    mkEnableOption
    mkOption
    types
    ;
in
{
  options.agindin.services.alloy = {
    enable = mkEnableOption "grafana-alloy (journal -> Loki shipper)";
    lokiHost = mkOption {
      type = types.str;
      description = "Host running loki service";
      default = "127.0.0.1";
    };
  };

  config = mkIf cfg.enable {
    services.alloy.enable = true;

    # Expose the alloy HTTP server (metrics + UI) on the same port the old
    # promtail module used so the grafana prometheus scrape config keeps working.
    services.alloy.extraFlags = [
      "--server.http.listen-addr=0.0.0.0:${toString globalVars.ports.alloy}"
    ];

    environment.etc."alloy/config.alloy".text = ''
      discovery.relabel "journal" {
        targets = []
        rule {
          source_labels = ["__journal__systemd_unit"]
          target_label  = "unit"
        }
      }

      loki.source.journal "default" {
        max_age       = "12h"
        relabel_rules = discovery.relabel.journal.rules
        forward_to    = [loki.write.default.receiver]
        labels        = {
          job  = "systemd-journal",
          host = "${config.networking.hostName}",
        }
      }

      loki.write "default" {
        endpoint {
          url = "http://${cfg.lokiHost}:${toString globalVars.ports.loki}/loki/api/v1/push"
        }
      }
    '';
  };
}
