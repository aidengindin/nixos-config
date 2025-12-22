{ config, lib, globalVars, ... }:
let
  cfg = config.agindin.services.promtail;
  inherit (lib) mkIf mkEnableOption mkOption types;
in {
  options.agindin.services.promtail = {
    enable = mkEnableOption "promtail";
    lokiHost = mkOption {
      type = types.str;
      description = "Host running loki service";
      default = "127.0.0.1";
    };
  };
  
  config = mkIf cfg.enable {
    services.promtail = {
      enable = true;
      configuration = {
        server = {
          http_listen_port = globalVars.ports.promtail;
          grpc_listen_port = 0;
        };
        positions = {
          filename = "/tmp/promtail_positions.yml";
        };
        clients = [{
          url = "http://${cfg.lokiHost}:${toString globalVars.ports.loki}/loki/api/v1/push";
        }];
        scrape_configs = [{
          job_name = "journal";
          journal = {
            max_age = "12h";
            labels = {
              job = "systemd-journal";
              host = config.networking.hostName;
            };
          };
          relabel_configs = [{
            source_labels = [ "__journal__systemd_unit" ];
            target_label = "unit";
          }];
        }];
      };
    };
  };
}
