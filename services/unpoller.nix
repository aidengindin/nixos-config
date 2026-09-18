{
  config,
  lib,
  globalVars,
  ...
}:
let
  cfg = config.agindin.services.unpoller;
  inherit (lib)
    mkIf
    mkOption
    mkEnableOption
    types
    ;
in
{
  options.agindin.services.unpoller = {
    enable = mkEnableOption "unpoller (UniFi -> Prometheus exporter)";
    controllerUrl = mkOption {
      type = types.str;
      default = "https://10.88.88.1";
      description = "URL of the UniFi controller (UniFi OS consoles need no port)";
    };
    user = mkOption {
      type = types.str;
      default = "unpoller";
      description = "Local read-only UniFi user";
    };
    passwordFile = mkOption {
      type = types.path;
      default = ../secrets/unpoller-password.age;
      description = "Age file containing the UniFi user's password";
    };
  };

  config = mkIf cfg.enable {
    age.secrets.unpollerPassword = {
      file = cfg.passwordFile;
      owner = "unpoller-exporter";
      group = "unpoller-exporter";
      mode = "0400";
    };

    services.prometheus.exporters.unpoller = {
      enable = true;
      listenAddress = "127.0.0.1";
      port = globalVars.ports.unpoller;
      log.prometheusErrors = true;
      controllers = [
        {
          url = cfg.controllerUrl;
          inherit (cfg) user;
          pass = config.age.secrets.unpollerPassword.path;
          # UniFi consoles ship a self-signed certificate.
          verify_ssl = false;
          save_dpi = false;
          save_sites = true;
        }
      ];
    };
  };
}
