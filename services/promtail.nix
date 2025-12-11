{ config, lib, pkgs, ... }:
let
  cfg = config.agindin.services.promtail;
  inherit (lib) mkIf mkEnableOption mkOption types;

  lokiPort = 10004;
  promtailPort = 10005;
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
          http_listen_port = promtailPort;
          grpc_listen_port = 0;
        };
        positions = {
          filename = "/tmp/positions.yml";
        };
        clients = [{
          url = "http://${cfg.lokiHost}:${toString lokiPort}";
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
          relabelConfigs = [{
            source_labels = [ "__journal__systemd_unit" ];
            target_label = "unit";
          }];
        }];
      };
    };
  };
}
