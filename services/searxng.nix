{ config, lib, pkgs, ... }:
let
  cfg = config.agindin.services.searxng;
  inherit (lib) mkIf mkEnableOption mkOption types;
in
{
  options.agindin.services.searxng = {
    enable = mkEnableOption "searxng";
    host = mkOption {
      type = types.str;
      default = "searxng.gindin.xyz";
    };
    interface = mkOption {
      type = types.str;
      default = "enp1s0";
      description = "Host network interface to use for NAT";
    };
  };

  config = mkIf cfg.enable {
    services.searxng = {
      enable = true;
      redisCreateLocally = true;

      uwsgiConfig = {
        socket = "/run/searx/searx.sock";
        http = ":8888";
        chmod-socket = "660";
      };

      settings = {
        general = {
          debug = false;
          instance_name = "SearxNG";
          donation_url = false;
          contact_url = false;
          privacypolicy_url = false;
        };

        server = {
          base_url = "https://${cfg.host}";
          port = 8888;
          bind_address = "127.0.0.1";
          public_instance = false;
        };
      };
    };
  };
}
